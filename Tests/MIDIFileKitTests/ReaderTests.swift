//
//  ReaderTests.swift
//  MIDIFileKitTests
//
//  Created by David Sherlock on 2026.
//
//  The parser, against files whose contents are known before they are parsed.
//

import XCTest
@testable import MIDIFileKit

final class ReaderTests: XCTestCase {

    func testReadsASingleNote() throws {
        let data = MIDIBuilder.file(MIDIBuilder.note(60, at: 0, length: 480))
        let file = try MIDIReader.read(data)

        XCTAssertEqual(file.format, 0)
        XCTAssertEqual(file.division, .ticksPerQuarterNote(480))
        XCTAssertEqual(file.notes.count, 1)

        let note = try XCTUnwrap(file.notes.first)
        XCTAssertEqual(note.pitch.number, 60)
        XCTAssertEqual(note.pitch.name, "C4")
        XCTAssertEqual(note.velocity, 100)
        XCTAssertEqual(note.startTicks, 0)
        XCTAssertEqual(note.durationTicks, 480)
        XCTAssertEqual(note.durationBeats, 1, accuracy: 0.0001)
    }

    /// Note-off is usually written as a note-on with velocity zero. Both spellings must end
    /// the note; reading the second as a note that sounds is how every note in a file ends
    /// up lasting until the end of it.
    func testZeroVelocityNoteOnEndsTheNote() throws {
        let data = MIDIBuilder.file([
            MIDIBuilder.noteOn(64, delta: 0),
            MIDIBuilder.noteOffAsZeroVelocity(64, delta: 240),
            MIDIBuilder.noteOn(67, delta: 240),
            MIDIBuilder.noteOffAsZeroVelocity(67, delta: 240)
        ])
        let file = try MIDIReader.read(data)

        XCTAssertEqual(file.notes.count, 2)
        XCTAssertEqual(file.notes.map(\.durationTicks), [240, 240])
        XCTAssertEqual(file.notes.map(\.pitch.number), [64, 67])
        XCTAssertTrue(file.notes.allSatisfy { $0.velocity > 0 },
                      "a velocity-zero note-on must never become a sounding note")
    }

    /// An event may omit its status byte, meaning "same as the last one". A reader that does
    /// not track it desynchronises and produces plausible wrong notes rather than an error.
    func testRunningStatusIsCarried() throws {
        let data = MIDIBuilder.file([
            MIDIBuilder.noteOn(60, velocity: 90, delta: 0),
            MIDIBuilder.runningStatus([62, 90], delta: 0),      // note-on, status implied
            MIDIBuilder.runningStatus([60, 0], delta: 480),     // note-off by zero velocity
            MIDIBuilder.runningStatus([62, 0], delta: 0)
        ])
        let file = try MIDIReader.read(data)

        XCTAssertEqual(file.notes.count, 2)
        XCTAssertEqual(Set(file.notes.map(\.pitch.number)), [60, 62])
        XCTAssertTrue(file.notes.allSatisfy { $0.durationTicks == 480 })
    }

    /// The edge implementations miss: a meta event in the middle of a run neither becomes
    /// the running status nor clears it.
    func testMetaEventDoesNotDisturbRunningStatus() throws {
        let data = MIDIBuilder.file([
            MIDIBuilder.noteOn(60, delta: 0),
            MIDIBuilder.marker("section", delta: 0),
            MIDIBuilder.runningStatus([60, 0], delta: 480)
        ])
        let file = try MIDIReader.read(data)

        XCTAssertEqual(file.notes.count, 1)
        XCTAssertEqual(file.notes.first?.durationTicks, 480)
        XCTAssertEqual(file.markers.first?.text, "section")
    }

    /// SysEx likewise must not become the running status.
    func testSysExDoesNotDisturbRunningStatus() throws {
        let data = MIDIBuilder.file([
            MIDIBuilder.noteOn(72, delta: 0),
            MIDIBuilder.sysEx([0x7E, 0x7F, 0x09, 0x01, 0xF7], delta: 0),
            MIDIBuilder.runningStatus([72, 0], delta: 120)
        ])
        let file = try MIDIReader.read(data)

        XCTAssertEqual(file.notes.count, 1)
        XCTAssertEqual(file.notes.first?.durationTicks, 120)
    }

    /// The same pitch struck again before the first is released. Pairing oldest-on to
    /// next-off is what a synthesiser does; pairing newest first gives one note of zero
    /// length and one that runs too long.
    func testOverlappingSamePitchPairsOldestFirst() throws {
        let data = MIDIBuilder.file([
            MIDIBuilder.noteOn(60, velocity: 80, delta: 0),
            MIDIBuilder.noteOn(60, velocity: 110, delta: 240),
            MIDIBuilder.noteOff(60, delta: 240),
            MIDIBuilder.noteOff(60, delta: 240)
        ])
        let file = try MIDIReader.read(data)

        XCTAssertEqual(file.notes.count, 2)
        let sorted = file.notes.sorted { $0.startTicks < $1.startTicks }
        XCTAssertEqual(sorted[0].startTicks, 0)
        XCTAssertEqual(sorted[0].durationTicks, 480)
        XCTAssertEqual(sorted[0].velocity, 80)
        XCTAssertEqual(sorted[1].startTicks, 240)
        XCTAssertEqual(sorted[1].durationTicks, 480)
        XCTAssertEqual(sorted[1].velocity, 110)
    }

    /// A note with no note-off is ended at the last tick of the track rather than dropped:
    /// a file that ends mid-note is common, and discarding it loses more than it protects.
    func testUnterminatedNoteIsClosedAtTheEnd() throws {
        let data = MIDIBuilder.file([
            MIDIBuilder.noteOn(55, delta: 0),
            MIDIBuilder.noteOn(59, delta: 960),
            MIDIBuilder.noteOff(59, delta: 240)
        ])
        let file = try MIDIReader.read(data)

        XCTAssertEqual(file.notes.count, 2)
        let hanging = try XCTUnwrap(file.notes.first { $0.pitch.number == 55 })
        XCTAssertEqual(hanging.durationTicks, 1200, "should end at the track's last tick")
    }

    func testReadsMultipleTracksAndNamesThem() throws {
        var builder = MIDIBuilder()
        builder.format = 1
        builder.tracks = [
            [MIDIBuilder.trackName("Tempo Map"), MIDIBuilder.tempo(bpm: 138)],
            [MIDIBuilder.trackName("Bass Layer 1")] + MIDIBuilder.note(36, at: 0, length: 480),
            [MIDIBuilder.trackName("Sub")] + MIDIBuilder.note(31, at: 0, length: 960)
        ]
        let file = try MIDIReader.read(builder.build())

        XCTAssertEqual(file.format, 1)
        XCTAssertEqual(file.tracks.count, 3)
        XCTAssertEqual(file.trackNames, ["Tempo Map", "Bass Layer 1", "Sub"])
        XCTAssertEqual(file.notes.count, 2)
        XCTAssertEqual(file.tempoMap.initial.bpm, 138, accuracy: 0.1)
    }

    /// A tempo on track 0 governs notes on track 2. Building notes per-track and converting
    /// afterwards is the only ordering that gets this right.
    func testTempoFromAnotherTrackAppliesToTheseNotes() throws {
        var builder = MIDIBuilder()
        builder.format = 1
        builder.tracks = [
            [MIDIBuilder.tempo(bpm: 60)],
            MIDIBuilder.note(60, at: 0, length: 480)
        ]
        let file = try MIDIReader.read(builder.build())

        let note = try XCTUnwrap(file.notes.first)
        XCTAssertEqual(note.durationSeconds, 1.0, accuracy: 0.001,
                       "one quarter note at 60 bpm is one second")
    }

    /// Chunks that are not MTrk are skippable by design, and files in the wild carry them.
    func testUnknownChunksAreSkipped() throws {
        var bytes = [UInt8](MIDIBuilder.file(MIDIBuilder.note(60, at: 0, length: 480)))
        let vendor: [UInt8] = [UInt8]("XFIR".utf8) + [0, 0, 0, 4] + [1, 2, 3, 4]
        bytes.insert(contentsOf: vendor, at: 14)      // straight after the 14-byte header
        let file = try MIDIReader.read(Data(bytes))

        XCTAssertEqual(file.notes.count, 1)
    }

    func testReadsMarkersTimeSignaturesAndDeclaredKeys() throws {
        let data = MIDIBuilder.file([
            MIDIBuilder.timeSignature(3, 4),
            MIDIBuilder.keySignature(accidentals: -3, minor: true),
            MIDIBuilder.marker("drop", delta: 960)
        ])
        let file = try MIDIReader.read(data)

        XCTAssertEqual(file.timeSignatures.first?.label, "3/4")
        XCTAssertEqual(file.timeSignatures.first?.beatsPerBar, 3)
        XCTAssertEqual(file.declaredKeys.first?.name, "Cm")
        XCTAssertEqual(file.markers.first?.text, "drop")
        XCTAssertEqual(file.markers.first?.atTicks, 960)
    }

    func testPercussionChannelIsFlagged() throws {
        let data = MIDIBuilder.file(MIDIBuilder.note(36, at: 0, length: 120, channel: 9))
        let file = try MIDIReader.read(data)

        XCTAssertTrue(file.notes.first?.isPercussion == true)
        XCTAssertTrue(file.tracks.first?.isPercussion == true)
    }
}
