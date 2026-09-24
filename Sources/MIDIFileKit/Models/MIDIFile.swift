//
//  MIDIFile.swift
//  MIDIFileKit
//
//  Created by David Sherlock on 2026.
//
//  A parsed Standard MIDI File.
//

import Foundation

/// Everything a Standard MIDI File contains, read.
public struct MIDIFile: Codable, Hashable, Sendable {

    /// 0 (one track), 1 (parallel tracks, one song) or 2 (independent sequences).
    ///
    /// The distinction that matters is 2: its tracks are separate pieces played one after
    /// another, so pooling their notes into one analysis is meaningless. See ``isSequenceBundle``.
    public let format: Int

    /// What one tick means.
    public let division: Division

    /// Tracks in file order.
    public let tracks: [Track]

    /// Every tempo, with the tick-to-second arithmetic.
    public let tempoMap: TempoMap

    /// Time signatures in tick order. Never empty: defaults to 4/4.
    public let timeSignatures: [TimeSignature]

    /// The key signature meta events, as written.
    ///
    /// Read ``KeySignature`` before believing these — every one of the 895 found in the
    /// measured corpus said C major, and none of those files were. ``estimatedKey`` is the
    /// field to use.
    public let declaredKeys: [KeySignature]

    /// Marker meta events — section labels, where a file has them (19% of the corpus).
    public let markers: [(atTicks: Int, text: String)]

    /// Text meta events other than names and markers.
    public let texts: [(atTicks: Int, text: String)]

    /// Every program change in the file, in tick order.
    ///
    /// Empty for loop libraries — the measured corpus had none at all across 1,200 files —
    /// and populated for full arrangements. See ``Instrument`` for why ``trackNames`` is the
    /// fallback rather than an error.
    public let instruments: [Instrument]

    /// Control changes — sustain pedal and the like — in file order.
    public let controlChanges: [ControlChange]

    /// Pitch bends in file order; 8192 is centre.
    public let pitchBends: [PitchBend]

    /// Every note in the file, in start order, across all tracks.
    public var notes: [Note] {
        tracks.flatMap(\.notes).sorted {
            $0.startTicks == $1.startTicks ? $0.pitch < $1.pitch : $0.startTicks < $1.startTicks
        }
    }

    /// Whether the tracks are independent pieces rather than parts of one.
    public var isSequenceBundle: Bool { format == 2 }

    /// The last tick any note stops sounding.
    public var endTicks: Int { notes.map(\.endTicks).max() ?? 0 }

    /// Total length in seconds.
    public var duration: Double { tempoMap.seconds(atTicks: endTicks) }

    /// Total length in quarter notes.
    public var beats: Double { tempoMap.beats(atTicks: endTicks) }

    /// Length in bars under the first time signature, or nil if that cannot be computed.
    ///
    /// Uses the FIRST signature only and is therefore wrong for a file that changes metre.
    /// It is offered because 99.9% of the measured corpus is 4/4 throughout — 1,214 files of
    /// 1,215 — and a bar count is the unit people think in.
    public var bars: Double? {
        guard let first = timeSignatures.first, first.beatsPerBar > 0 else { return nil }
        guard timeSignatures.count == 1 else { return nil }
        return beats / first.beatsPerBar
    }

    /// The lowest and highest note in the file.
    public var range: ClosedRange<Pitch>? {
        let all = notes.map(\.pitch)
        guard let low = all.min(), let high = all.max() else { return nil }
        return low ... high
    }

    /// Track names, which in practice are the instrument names. See ``Track/name``.
    public var trackNames: [String] { tracks.compactMap(\.name) }

    /// One entry per channel that actually plays something, in channel order.
    ///
    /// The view that makes a full multi-instrument arrangement legible: what plays on each
    /// of the sixteen channels, named from the program change where there is one and the
    /// track name where there is not. A single-channel loop yields exactly one entry, so the
    /// same call works for both shapes of file.
    public var channels: [Channel] {
        let all = notes
        return Set(all.map(\.channel)).sorted().map { number in
            let mine = all.filter { $0.channel == number }
            let pitches = mine.map(\.pitch)
            let tracksHere = Set(mine.map(\.track))
            return Channel(
                number: number,
                instruments: instruments.filter { $0.channel == number },
                trackNames: tracks.filter { tracksHere.contains($0.index) }.compactMap(\.name),
                noteCount: mine.count,
                range: pitches.min().flatMap { low in pitches.max().map { low ... $0 } })
        }
    }

    /// Whether this file carries more than one channel of material.
    public var isMultiChannel: Bool { Set(notes.map(\.channel)).count > 1 }

    // Markers and texts are tuple arrays for ergonomics at the call site; Codable needs
    // them spelled out, which is why this type has hand-written coding rather than synthesised.
    private enum CodingKeys: String, CodingKey {
        case format, division, tracks, tempoMap, timeSignatures, declaredKeys
        case markers, texts, instruments, controlChanges, pitchBends
    }

    private struct TextEvent: Codable, Hashable, Sendable {
        let atTicks: Int
        let text: String
    }

    init(format: Int, division: Division, tracks: [Track], tempoMap: TempoMap,
         timeSignatures: [TimeSignature], declaredKeys: [KeySignature],
         markers: [(atTicks: Int, text: String)], texts: [(atTicks: Int, text: String)],
         instruments: [Instrument] = [], controlChanges: [ControlChange] = [], pitchBends: [PitchBend] = []) {
        self.format = format
        self.division = division
        self.tracks = tracks
        self.tempoMap = tempoMap
        self.timeSignatures = timeSignatures.isEmpty ? [.default] : timeSignatures
        self.declaredKeys = declaredKeys
        self.markers = markers
        self.texts = texts
        self.instruments = instruments
        self.controlChanges = controlChanges
        self.pitchBends = pitchBends
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(Int.self, forKey: .format)
        division = try c.decode(Division.self, forKey: .division)
        tracks = try c.decode([Track].self, forKey: .tracks)
        tempoMap = try c.decode(TempoMap.self, forKey: .tempoMap)
        timeSignatures = try c.decode([TimeSignature].self, forKey: .timeSignatures)
        declaredKeys = try c.decode([KeySignature].self, forKey: .declaredKeys)
        markers = try c.decode([TextEvent].self, forKey: .markers).map { ($0.atTicks, $0.text) }
        texts = try c.decode([TextEvent].self, forKey: .texts).map { ($0.atTicks, $0.text) }
        instruments = try c.decodeIfPresent([Instrument].self, forKey: .instruments) ?? []
        controlChanges = try c.decodeIfPresent([ControlChange].self, forKey: .controlChanges) ?? []
        pitchBends = try c.decodeIfPresent([PitchBend].self, forKey: .pitchBends) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(format, forKey: .format)
        try c.encode(division, forKey: .division)
        try c.encode(tracks, forKey: .tracks)
        try c.encode(tempoMap, forKey: .tempoMap)
        try c.encode(timeSignatures, forKey: .timeSignatures)
        try c.encode(declaredKeys, forKey: .declaredKeys)
        try c.encode(markers.map { TextEvent(atTicks: $0.atTicks, text: $0.text) }, forKey: .markers)
        try c.encode(texts.map { TextEvent(atTicks: $0.atTicks, text: $0.text) }, forKey: .texts)
        try c.encode(instruments, forKey: .instruments)
        try c.encode(controlChanges, forKey: .controlChanges)
        try c.encode(pitchBends, forKey: .pitchBends)
    }

    public static func == (lhs: MIDIFile, rhs: MIDIFile) -> Bool {
        lhs.format == rhs.format && lhs.division == rhs.division && lhs.tracks == rhs.tracks
            && lhs.tempoMap == rhs.tempoMap && lhs.timeSignatures == rhs.timeSignatures
            && lhs.declaredKeys == rhs.declaredKeys && lhs.instruments == rhs.instruments
            && lhs.controlChanges == rhs.controlChanges && lhs.pitchBends == rhs.pitchBends
            && lhs.markers.map(\.atTicks) == rhs.markers.map(\.atTicks)
            && lhs.markers.map(\.text) == rhs.markers.map(\.text)
            && lhs.texts.map(\.atTicks) == rhs.texts.map(\.atTicks)
            && lhs.texts.map(\.text) == rhs.texts.map(\.text)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(format)
        hasher.combine(tracks)
        hasher.combine(tempoMap)
    }
}
