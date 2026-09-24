//
//  WriterTests.swift
//  MIDIFileKitTests
//
//  Created by David Sherlock on 2026.
//
//  Writing, and the round trip.
//
//  The round trip is the strongest test in this package, because the reader and the writer
//  share no code: the reader decodes running status, implied note-offs and packed deltas that
//  the writer never emits, and the writer decides ordering and framing the reader never
//  inspects. A note that survives write → read came through two independent implementations
//  agreeing, which is the same argument that makes ``MIDIBuilder`` worth keeping separate.
//

import XCTest
@testable import MIDIFileKit

final class WriterTests: XCTestCase {

    // MARK: Round trip

    func testNotesSurviveARoundTrip() throws {
        var song = Composition(bpm: 138)
        song.addTrack(name: "Bass", channel: 0) { track in
            track.note("F#2", atBeat: 0, lasting: 0.5, velocity: 110)
            track.note("F#2", atBeat: 1, lasting: 0.5, velocity: 90)
            track.note("A2", atBeat: 2, lasting: 1.0)
            track.note("C#3", atBeat: 3, lasting: 1.0)
        }
        let original = song.build()
        let reread = try MIDIReader.read(try original.data())

        XCTAssertEqual(reread.notes.count, 4)
        XCTAssertEqual(reread.notes.map(\.pitch.name), ["F#2", "F#2", "A2", "C#3"])
        XCTAssertEqual(reread.notes.map(\.velocity), [110, 90, 100, 100])
        XCTAssertEqual(reread.notes.map(\.startTicks), [0, 480, 960, 1440])
        XCTAssertEqual(reread.notes.map(\.durationTicks), [240, 240, 480, 480])
        XCTAssertEqual(reread.tempoMap.initial.bpm, 138, accuracy: 0.1)
    }

    func testEveryPitchSurvivesARoundTrip() throws {
        var song = Composition()
        song.addTrack(name: "Sweep") { track in
            for number in 0 ..< 128 {
                track.note(number, atBeat: Double(number), lasting: 0.5)
            }
        }
        let reread = try MIDIReader.read(try song.build().data())

        XCTAssertEqual(reread.notes.count, 128)
        XCTAssertEqual(reread.notes.map(\.pitch.number), Array(0 ..< 128))
    }

    func testMultipleTracksAndChannelsSurvive() throws {
        var song = Composition(bpm: 128)
        song.addTrack(name: "Piano", channel: 0, program: 0) { $0.chord(["C4", "E4", "G4"], atBeat: 0, lasting: 4) }
        song.addTrack(name: "Bass", channel: 1, program: 35) { $0.note("C2", atBeat: 0, lasting: 4) }
        song.addTrack(name: "Drums", channel: 9) { track in
            for beat in 0 ..< 4 { track.note(36, atBeat: Double(beat), lasting: 0.25) }
        }
        let reread = try MIDIReader.read(try song.build().data())

        XCTAssertEqual(reread.format, 1)
        XCTAssertEqual(reread.tracks.count, 3)
        XCTAssertEqual(reread.trackNames, ["Piano", "Bass", "Drums"])
        XCTAssertEqual(reread.channels.map(\.number), [0, 1, 9])
        // The drum track was given no program change, so its label falls back to the track
        // name — "Drums" tells a reader more than the General MIDI kit name would.
        XCTAssertEqual(reread.channels.map(\.label),
                       ["Acoustic Grand Piano", "Fretless Bass", "Drums"])
        XCTAssertTrue(reread.isMultiChannel)
    }

    func testTempoAndMetreSurvive() throws {
        var song = Composition(bpm: 174, timeSignature: (3, 4))
        song.addTrack(name: "x") { $0.note("C4", atBeat: 0, lasting: 3) }
        let reread = try MIDIReader.read(try song.build().data())

        XCTAssertEqual(reread.tempoMap.single?.bpm ?? 0, 174, accuracy: 0.1)
        XCTAssertEqual(reread.timeSignatures.first?.label, "3/4")
        XCTAssertEqual(reread.bars ?? 0, 1, accuracy: 0.001)
    }

    func testMarkersSurvive() throws {
        var song = Composition(bpm: 140)
        song.markers = [(0, "intro"), (16, "drop")]
        song.addTrack(name: "x") { $0.note("C4", atBeat: 0, lasting: 1) }
        let reread = try MIDIReader.read(try song.build().data())

        XCTAssertEqual(reread.markers.map(\.text), ["intro", "drop"])
        XCTAssertEqual(reread.markers.map(\.atTicks), [0, 7680])
    }

    /// A track name over 127 characters needs a multi-byte length. Writing it as one byte
    /// corrupts every event after it, and the file still opens — it just reads wrong.
    func testLongTrackNameIsLengthEncodedCorrectly() throws {
        // No trailing space: the reader trims track names, and that is not what is under test.
        let long = String(repeating: "Bass Layer ", count: 30)
            .trimmingCharacters(in: .whitespaces)          // 329 characters
        var song = Composition()
        song.addTrack(name: long) { $0.note("C4", atBeat: 0, lasting: 1) }
        let reread = try MIDIReader.read(try song.build().data())

        XCTAssertEqual(reread.tracks.first?.name, long)
        XCTAssertEqual(reread.notes.count, 1, "the note after a long name must survive")
    }

    /// A file read from disk, written back out, and read again must be the same file.
    func testReadWriteReadIsStable() throws {
        let source = MIDIBuilder.file(
            [MIDIBuilder.trackName("Massive 1"), MIDIBuilder.tempo(bpm: 136),
             MIDIBuilder.timeSignature(4, 4), MIDIBuilder.marker("build")]
            + MIDIBuilder.note(45, at: 0, length: 480)
            + MIDIBuilder.note(48, at: 0, length: 960)
            + MIDIBuilder.note(52, at: 240, length: 480))
        let first = try MIDIReader.read(source)
        let second = try MIDIReader.read(try first.data())
        let third = try MIDIReader.read(try second.data())

        XCTAssertEqual(second.notes.map(\.pitch.number), first.notes.map(\.pitch.number))
        XCTAssertEqual(second.notes.map(\.startTicks), first.notes.map(\.startTicks))
        XCTAssertEqual(second.notes.map(\.durationTicks), first.notes.map(\.durationTicks))
        XCTAssertEqual(third.notes.map(\.startTicks), second.notes.map(\.startTicks))
        XCTAssertEqual(second.trackNames, first.trackNames)
        XCTAssertEqual(second.markers.map(\.text), first.markers.map(\.text))
    }

    /// A note released exactly as the next is struck must not read back as an overlap.
    func testAdjacentNotesDoNotOverlapAfterARoundTrip() throws {
        var song = Composition()
        song.addTrack(name: "line") { track in
            track.note("C4", atBeat: 0, lasting: 1)
            track.note("D4", atBeat: 1, lasting: 1)
            track.note("C4", atBeat: 2, lasting: 1)
        }
        let reread = try MIDIReader.read(try song.build().data())

        XCTAssertEqual(reread.notes.count, 3)
        XCTAssertTrue(reread.chords(minimumVoices: 2).isEmpty,
                      "nothing here sounds together, so nothing should read as a chord")
    }

    // MARK: Analysis of what was built

    /// Building and then analysing is the loop that makes this useful, so it is tested.
    ///
    /// The progression is Am–Dm–E–Am and not the more obvious Am–F–C–G, because that one is
    /// genuinely ambiguous: it is the seven notes of C major with C as the heaviest class, and
    /// the estimator calls it C major at r=0.94 — defensibly, since the same vamp is as often
    /// analysed as C major. A test whose right answer is arguable tests nothing. The E chord
    /// here supplies a G#, which is not in C major, and that settles it.
    func testABuiltProgressionAnalysesAsItself() throws {
        var song = Composition(bpm: 128)
        song.addTrack(name: "Pad", channel: 0, program: 48) { track in
            track.chord(["A3", "C4", "E4"], atBeat: 0, lasting: 4)       // Am
            track.chord(["D3", "F3", "A3"], atBeat: 4, lasting: 4)       // Dm
            track.chord(["E3", "G#3", "B3"], atBeat: 8, lasting: 4)      // E  — the G# decides it
            track.chord(["A3", "C4", "E4"], atBeat: 12, lasting: 4)      // Am
        }
        let file = song.build()

        let chords = file.chords(minimumTicks: 8)
        XCTAssertEqual(chords.compactMap(\.name), ["Am", "Dm", "E", "Am"])

        let key = try XCTUnwrap(file.estimatedKey)
        XCTAssertEqual(key.rootName, "A")
        XCTAssertEqual(key.mode, .minor, "the G# puts this outside C major")
        XCTAssertTrue(key.isWellSupported)
    }

    // MARK: Pitch names

    func testPitchNamesParse() {
        XCTAssertEqual(Composition.pitch(named: "C4"), 60)
        XCTAssertEqual(Composition.pitch(named: "C-1"), 0)
        XCTAssertEqual(Composition.pitch(named: "G9"), 127)
        XCTAssertEqual(Composition.pitch(named: "F#2"), 42)
        XCTAssertEqual(Composition.pitch(named: "Gb2"), 42, "flats are accepted on input")
        XCTAssertEqual(Composition.pitch(named: "a4"), 69, "case does not matter")
        XCTAssertNil(Composition.pitch(named: "H4"), "no such letter")
        XCTAssertNil(Composition.pitch(named: "C"), "an octave is required")
        XCTAssertNil(Composition.pitch(named: "C10"), "past the top of the range")
        XCTAssertNil(Composition.pitch(named: ""))
    }

    func testUnparseableNoteNameIsReportedRatherThanSilentlyDropped() {
        var song = Composition()
        var accepted = true
        song.addTrack(name: "x") { track in
            accepted = track.note("H4", atBeat: 0, lasting: 1)
        }
        XCTAssertFalse(accepted)
        XCTAssertTrue(song.build().notes.isEmpty)
    }

    // MARK: Guards

    /// Velocity zero is a note-off, not a quiet note. Writing it would produce a file whose
    /// notes never sound and which reads back with half the events missing.
    func testZeroVelocityIsRaisedToOne() throws {
        var song = Composition()
        song.addTrack(name: "x") { $0.note("C4", atBeat: 0, lasting: 1, velocity: 0) }
        let reread = try MIDIReader.read(try song.build().data())

        XCTAssertEqual(reread.notes.count, 1)
        XCTAssertEqual(reread.notes.first?.velocity, 1)
    }

    /// SMPTE division is refused rather than written as ticks-per-quarter-note, which would
    /// silently change what every timestamp in the file means.
    func testSMPTEDivisionIsRefusedRatherThanMiswritten() throws {
        let raw = UInt16(bitPattern: Int16(Int8(-25)) << 8) | 40
        let file = try MIDIReader.read(MIDIBuilder.file(MIDIBuilder.note(60, at: 0, length: 500),
                                                        division: raw))
        XCTAssertThrowsError(try file.data()) { error in
            XCTAssertEqual(error as? MIDIFileError, .invalidDivision)
        }
    }

    /// A zero-length note made the writer emit that note's own off before its own on, which
    /// left the reader with an open note that swallowed the next note's off — and every
    /// duration after it in the track was wrong. Found by round-tripping the corpus: four
    /// files, all acid lines. The note is widened to one tick instead.
    func testZeroLengthNoteDoesNotCorruptTheRestOfTheTrack() throws {
        let source = MIDIBuilder.file([
            MIDIBuilder.noteOn(52, delta: 0),
            MIDIBuilder.noteOff(52, delta: 0),          // zero length
            MIDIBuilder.noteOn(52, delta: 120),
            MIDIBuilder.noteOff(52, delta: 360),
            MIDIBuilder.noteOn(52, delta: 120),
            MIDIBuilder.noteOff(52, delta: 240)
        ])
        let first = try MIDIReader.read(source)
        XCTAssertEqual(first.notes.map(\.durationTicks), [0, 360, 240])

        let reread = try MIDIReader.read(try first.data())
        XCTAssertEqual(reread.notes.count, 3, "no note may be lost or merged")
        XCTAssertEqual(reread.notes.map(\.startTicks), first.notes.map(\.startTicks))
        XCTAssertEqual(reread.notes.map(\.durationTicks), [1, 360, 240],
                       "the zero-length note widens to one tick; the others are untouched")
    }

    /// An empty track name is not a name. The reader used to report "" where the writer
    /// omitted the event entirely, so a file that was read and written back lost it.
    func testEmptyTrackNameIsNilAndSurvivesARoundTrip() throws {
        let empty: [UInt8] = [0xFF, 0x03, 0x00]
        let source = MIDIBuilder.file([MIDIBuilder.Event(delta: 0, bytes: empty)]
                                      + MIDIBuilder.note(60, at: 0, length: 480))
        let first = try MIDIReader.read(source)
        XCTAssertNil(first.tracks.first?.name)

        let reread = try MIDIReader.read(try first.data())
        XCTAssertEqual(reread.trackNames, first.trackNames)
        XCTAssertEqual(reread.notes.count, 1)
    }

    func testAnEmptyCompositionWritesAValidFile() throws {
        let reread = try MIDIReader.read(try Composition().build().data())
        XCTAssertTrue(reread.notes.isEmpty)
        XCTAssertEqual(reread.tracks.count, 1)
    }

    func testWritesToDiskAndReadsBack() throws {
        var song = Composition(bpm: 140)
        song.addTrack(name: "Lead") { $0.note("F#4", atBeat: 0, lasting: 2) }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("midifilekit-\(UUID().uuidString).mid")
        defer { try? FileManager.default.removeItem(at: url) }

        try song.build().write(to: url)
        let reread = try MIDIReader.read(contentsOf: url)

        XCTAssertEqual(reread.notes.first?.pitch.name, "F#4")
        XCTAssertEqual(reread.tempoMap.initial.bpm, 140, accuracy: 0.1)
    }

    /// Sustain pedal written as controller 64 on the notes' channel, read back in order.
    func testControlChangesRoundTrip() throws {
        var composition = Composition(bpm: 120, timeSignature: (4, 4), ticksPerQuarterNote: 480)
        composition.addTrack(name: "piano", channel: 0, program: 0) { track in
            track.note(60, atBeat: 0, lasting: 1, velocity: 90)
            track.sustain(down: true, atBeat: 0.5)
            track.note(64, atBeat: 1, lasting: 1, velocity: 70)
            track.sustain(down: false, atBeat: 1.75)
            track.controlChange(1, value: 33, atBeat: 2)
        }
        let file = composition.build()
        XCTAssertEqual(file.controlChanges.map(\.controller), [64, 64, 1])
        let data = try MIDIWriter.data(for: file)
        let read = try MIDIReader.read(data)
        XCTAssertEqual(read.controlChanges.map { ($0.atTicks, $0.controller, $0.value) }.map { "\($0)" },
                       [(240, 64, 127), (840, 64, 0), (960, 1, 33)].map { "\($0)" })
        XCTAssertEqual(read.controlChanges.map(\.channel), [0, 0, 0])
        XCTAssertEqual(read.notes.map(\.velocity), [90, 70])
    }

    /// Pitch bends written as 0xE0 (14-bit, low byte first) on the notes' channel, read back in order.
    func testPitchBendsRoundTrip() throws {
        var composition = Composition(bpm: 120, timeSignature: (4, 4), ticksPerQuarterNote: 480)
        composition.addTrack(name: "lead", channel: 1, program: 80) { track in
            track.note(69, atBeat: 0, lasting: 2, velocity: 100)
            track.pitchBend(PitchBend.centre, atBeat: 0)
            track.pitchBend(PitchBend.value(semitones: 1), atBeat: 0.5)
            track.pitchBend(PitchBend.value(semitones: -2), atBeat: 1)
            track.pitchBend(PitchBend.maximum, atBeat: 1.5)
        }
        let file = composition.build()
        XCTAssertEqual(file.pitchBends.map(\.value), [8192, 12288, 0, 16383])
        let data = try MIDIWriter.data(for: file)
        let read = try MIDIReader.read(data)
        XCTAssertEqual(read.pitchBends.map { ($0.atTicks, $0.value) }.map { "\($0)" },
                       [(0, 8192), (240, 12288), (480, 0), (720, 16383)].map { "\($0)" })
        XCTAssertEqual(read.pitchBends.map(\.channel), [1, 1, 1, 1])
        XCTAssertEqual(read.pitchBends[1].semitones(), 1, accuracy: 0.001)
        XCTAssertEqual(read.pitchBends[2].semitones(), -2, accuracy: 0.001)
        XCTAssertEqual(read.pitchBends[3].semitones(range: 12), 12, accuracy: 0.001)
        XCTAssertEqual(read.notes.map(\.pitch.number), [69])
    }
}
