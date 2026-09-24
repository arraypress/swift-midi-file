//
//  Composition.swift
//  MIDIFileKit
//
//  Created by David Sherlock on 2026.
//
//  Building a MIDI file from nothing.
//
//  ``MIDIFile`` is the shape of a file that was READ: every field is populated and every note
//  already knows its position in ticks, beats and seconds. Constructing one of those by hand
//  to write four notes is miserable, so this is the other door — you give it beats and it
//  works out ticks, and ``build()`` hands back a ``MIDIFile`` that ``MIDIWriter`` can serialise
//  and ``MIDIReader`` will read back identically.
//

import Foundation

/// Assembles a MIDI file from parts.
///
/// ```swift
/// var song = Composition(bpm: 138)
/// song.addTrack(name: "Bass", channel: 0) { track in
///     track.note("F#2", atBeat: 0, lasting: 0.5)
///     track.note("F#2", atBeat: 1, lasting: 0.5)
/// }
/// song.addTrack(name: "Pad", channel: 1, program: 48) { track in
///     track.chord(["F#4", "A4", "C#5"], atBeat: 0, lasting: 4)
/// }
/// try song.build().write(to: url)
/// ```
public struct Composition {

    /// Ticks per quarter note. 480 is what most DAWs write and what this defaults to.
    public var ticksPerQuarterNote: Int

    /// Quarter notes per minute.
    public var bpm: Double

    /// Beats per bar and the note value that gets the beat.
    public var timeSignature: (numerator: Int, denominator: Int)

    /// Section markers, in beats.
    public var markers: [(beat: Double, text: String)] = []

    private var tracks: [Builder] = []

    /// - Parameters:
    ///   - bpm: quarter notes per minute. Defaults to 120, which is what a file with no tempo
    ///     event means anyway.
    ///   - timeSignature: defaults to 4/4.
    ///   - ticksPerQuarterNote: the timing grid. Higher resolves finer; 480 divides cleanly by
    ///     3 and 4, so triplets and sixteenths both land on whole ticks.
    public init(bpm: Double = 120,
                timeSignature: (numerator: Int, denominator: Int) = (4, 4),
                ticksPerQuarterNote: Int = 480) {
        self.bpm = bpm
        self.timeSignature = timeSignature
        self.ticksPerQuarterNote = max(1, ticksPerQuarterNote)
    }

    /// One track being written.
    public struct Builder {

        public var name: String?
        public var channel: Int
        public var program: Int?
        fileprivate var pending: [(pitch: Int, beat: Double, length: Double, velocity: Int)] = []
        fileprivate var controls: [(controller: Int, value: Int, beat: Double)] = []
        fileprivate var bends: [(value: Int, beat: Double)] = []

        fileprivate init(name: String?, channel: Int, program: Int?) {
            self.name = name
            self.channel = channel
            self.program = program
        }

        /// Add a note by MIDI number.
        ///
        /// - Parameters:
        ///   - pitch: 0…127.
        ///   - beat: quarter notes from the start of the file.
        ///   - lasting: length in quarter notes.
        ///   - velocity: 1…127. Zero is not a velocity — it means note-off — so it is raised
        ///     to 1 rather than silently producing a note that never sounds.
        public mutating func note(_ pitch: Int, atBeat beat: Double, lasting: Double,
                                  velocity: Int = 100) {
            pending.append((min(127, max(0, pitch)), max(0, beat), max(0, lasting),
                            min(127, max(1, velocity))))
        }

        /// Add a note by name — "F#2", "C4", "Bb3".
        ///
        /// Flats are accepted on input even though this library spells everything with sharps,
        /// because a person writing a bassline thinks in whichever the key uses.
        @discardableResult
        public mutating func note(_ name: String, atBeat beat: Double, lasting: Double,
                                  velocity: Int = 100) -> Bool {
            guard let pitch = Composition.pitch(named: name) else { return false }
            note(pitch, atBeat: beat, lasting: lasting, velocity: velocity)
            return true
        }

        /// Add several notes struck together.
        @discardableResult
        public mutating func chord(_ names: [String], atBeat beat: Double, lasting: Double,
                                   velocity: Int = 100) -> Bool {
            var allResolved = true
            for name in names {
                if !note(name, atBeat: beat, lasting: lasting, velocity: velocity) {
                    allResolved = false
                }
            }
            return allResolved
        }

        /// Add a control change on this track's channel — `sustain(down:atBeat:)` is the
        /// common case.
        public mutating func controlChange(_ controller: Int, value: Int, atBeat beat: Double) {
            controls.append((min(127, max(0, controller)), min(127, max(0, value)), max(0, beat)))
        }

        /// Add a pitch bend on this track's channel: a 14-bit value, 8192 at centre —
        /// `PitchBend.value(semitones:range:)` computes one from a bend in semitones.
        public mutating func pitchBend(_ value: Int, atBeat beat: Double) {
            bends.append((min(PitchBend.maximum, max(0, value)), max(0, beat)))
        }

        /// Sustain pedal down (127) or up (0) at `beat`.
        public mutating func sustain(down: Bool, atBeat beat: Double) {
            controlChange(ControlChange.sustainPedal, value: down ? 127 : 0, atBeat: beat)
        }

        /// Add notes already modelled — a phrase read from another file, transposed or not.
        public mutating func add(_ notes: [Note], beatsPerTick: Double) {
            for note in notes {
                pending.append((note.pitch.number,
                                Double(note.startTicks) * beatsPerTick,
                                Double(note.durationTicks) * beatsPerTick,
                                min(127, max(1, note.velocity))))
            }
        }
    }

    /// Add a track.
    ///
    /// - Parameters:
    ///   - name: the track name meta event. In a loop library this is what names the
    ///     instrument, so it is worth setting — see ``Track/name``.
    ///   - channel: 0…15. Channel 9 is percussion by convention.
    ///   - program: a General MIDI program, 0…127, written as a program change.
    public mutating func addTrack(name: String? = nil, channel: Int = 0, program: Int? = nil,
                                  _ build: (inout Builder) -> Void) {
        var builder = Builder(name: name, channel: min(15, max(0, channel)), program: program)
        build(&builder)
        tracks.append(builder)
    }

    /// Turn this into a ``MIDIFile``, ready to write or to analyse.
    ///
    /// Analysing what you just built is a real use: the key estimator and chord extractor work
    /// on it exactly as they would on a file from disk, which is how the tests check that a
    /// progression spells what it was meant to.
    public func build() -> MIDIFile {
        let ticks = Double(ticksPerQuarterNote)
        let division = Division.ticksPerQuarterNote(ticksPerQuarterNote)
        let tempo = Tempo(atTicks: 0,
                          microsecondsPerQuarterNote: Int((60_000_000 / max(1, bpm)).rounded()))
        let map = TempoMap(tempos: [tempo], division: division)

        let built = tracks.enumerated().map { index, builder in
            let notes = builder.pending
                .sorted { $0.beat < $1.beat }
                .map { pending -> Note in
                    let startTicks = Int((pending.beat * ticks).rounded())
                    let durationTicks = Int((pending.length * ticks).rounded())
                    return Note(pitch: Pitch(pending.pitch), velocity: pending.velocity,
                                channel: builder.channel, track: index,
                                startTicks: startTicks, durationTicks: durationTicks,
                                startBeats: pending.beat, durationBeats: pending.length,
                                startSeconds: map.seconds(atTicks: startTicks),
                                durationSeconds: map.seconds(atTicks: startTicks + durationTicks)
                                               - map.seconds(atTicks: startTicks))
                }
            return Track(index: index, name: builder.name, instrument: nil, notes: notes)
        }

        let instruments = tracks.enumerated().compactMap { index, builder in
            builder.program.map { Instrument(atTicks: 0, channel: builder.channel, program: $0) }
        }
        let controlChanges = tracks.flatMap { builder in
            builder.controls.map { ControlChange(atTicks: Int(($0.beat * ticks).rounded()), channel: builder.channel,
                                                 controller: $0.controller, value: $0.value) }
        }

        let pitchBends = tracks.flatMap { builder in
            builder.bends.map { PitchBend(atTicks: Int(($0.beat * ticks).rounded()), channel: builder.channel, value: $0.value) }
        }

        return MIDIFile(
            format: built.count > 1 ? 1 : 0,
            division: division,
            tracks: built,
            tempoMap: map,
            timeSignatures: [TimeSignature(atTicks: 0, numerator: timeSignature.numerator,
                                           denominator: timeSignature.denominator)],
            declaredKeys: [],
            markers: markers.map { (Int(($0.beat * ticks).rounded()), $0.text) },
            texts: [],
            instruments: instruments,
            controlChanges: controlChanges,
            pitchBends: pitchBends)
    }

    /// Parse a pitch name — "C4", "F#2", "Bb3", "Eb-1" — into a MIDI note number.
    ///
    /// Middle C is C4, matching ``Pitch/octave``.
    public static func pitch(named name: String) -> Int? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let letter = trimmed.first,
              let base = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11][String(letter).uppercased()]
        else { return nil }

        var index = trimmed.index(after: trimmed.startIndex)
        var accidental = 0
        while index < trimmed.endIndex, trimmed[index] == "#" || trimmed[index] == "b" {
            accidental += trimmed[index] == "#" ? 1 : -1
            index = trimmed.index(after: index)
        }
        guard let octave = Int(trimmed[index...]) else { return nil }

        let number = (octave + 1) * 12 + base + accidental
        return (0...127).contains(number) ? number : nil
    }
}
