//
//  TimingTests.swift
//  MIDIFileKitTests
//
//  Created by David Sherlock on 2026.
//
//  Ticks into beats and seconds — including across a tempo change, which is the only part
//  of this that is not multiplication.
//

import XCTest
@testable import MIDIFileKit

final class TimingTests: XCTestCase {

    func testDefaultTempoIs120BPM() throws {
        // A file with no tempo event is 120 bpm by definition, not by guess.
        let file = try MIDIReader.read(MIDIBuilder.file(MIDIBuilder.note(60, at: 0, length: 480)))
        XCTAssertEqual(file.tempoMap.initial.bpm, 120, accuracy: 0.001)
        XCTAssertEqual(file.notes.first?.durationSeconds ?? 0, 0.5, accuracy: 0.001)
    }

    func testTempoConvertsTicksToSeconds() throws {
        let data = MIDIBuilder.file([MIDIBuilder.tempo(bpm: 140)]
                                    + MIDIBuilder.note(60, at: 0, length: 480))
        let file = try MIDIReader.read(data)
        let expected = 60.0 / 140
        XCTAssertEqual(file.notes.first?.durationSeconds ?? 0, expected, accuracy: 0.001)
    }

    /// The case a naive reader gets wrong: it scales everything by the FIRST tempo, which
    /// files a ramp from 90 to 180 entirely under 90.
    func testSecondsAccumulateAcrossATempoChange() throws {
        let data = MIDIBuilder.file([
            MIDIBuilder.tempo(bpm: 60),                       // 1 s per quarter note
            MIDIBuilder.noteOn(60, delta: 0),
            MIDIBuilder.noteOff(60, delta: 960),              // 2 quarter notes = 2 s
            MIDIBuilder.tempo(bpm: 120, delta: 0),            // now 0.5 s per quarter note
            MIDIBuilder.noteOn(62, delta: 0),
            MIDIBuilder.noteOff(62, delta: 960)               // 2 quarter notes = 1 s
        ])
        let file = try MIDIReader.read(data)
        let notes = file.notes.sorted { $0.startTicks < $1.startTicks }

        XCTAssertEqual(file.tempoMap.tempos.count, 2)
        XCTAssertFalse(file.tempoMap.isConstant)
        XCTAssertNil(file.tempoMap.single, "a file that changes tempo has no single tempo")
        XCTAssertEqual(notes[0].durationSeconds, 2.0, accuracy: 0.01)
        XCTAssertEqual(notes[1].startSeconds, 2.0, accuracy: 0.01)
        XCTAssertEqual(notes[1].durationSeconds, 1.0, accuracy: 0.01)
        XCTAssertEqual(file.duration, 3.0, accuracy: 0.01)
    }

    /// ``TempoMap/single`` is the field a caller labelling a loop should use, and it must be
    /// nil rather than optimistic when the answer is "it depends".
    func testSingleTempoIsOnlyReportedWhenConstant() throws {
        let steady = try MIDIReader.read(MIDIBuilder.file([MIDIBuilder.tempo(bpm: 138)]
                                                          + MIDIBuilder.note(60, at: 0, length: 480)))
        XCTAssertEqual(steady.tempoMap.single?.bpm ?? 0, 138, accuracy: 0.1)
        XCTAssertTrue(steady.tempoMap.isConstant)
    }

    func testBeatsAndBarsUnderFourFour() throws {
        let data = MIDIBuilder.file([MIDIBuilder.timeSignature(4, 4)]
                                    + MIDIBuilder.note(60, at: 0, length: 480 * 16))
        let file = try MIDIReader.read(data)

        XCTAssertEqual(file.beats, 16, accuracy: 0.001)
        XCTAssertEqual(file.bars ?? 0, 4, accuracy: 0.001)
    }

    func testBarsUnderThreeFour() throws {
        let data = MIDIBuilder.file([MIDIBuilder.timeSignature(3, 4)]
                                    + MIDIBuilder.note(60, at: 0, length: 480 * 12))
        let file = try MIDIReader.read(data)
        XCTAssertEqual(file.bars ?? 0, 4, accuracy: 0.001)
    }

    /// A bar count computed from the first signature is wrong for a file that changes metre,
    /// so it is withheld rather than reported wrongly.
    func testBarsAreWithheldWhenTheMetreChanges() throws {
        let data = MIDIBuilder.file([
            MIDIBuilder.timeSignature(4, 4),
            MIDIBuilder.noteOn(60, delta: 0),
            MIDIBuilder.noteOff(60, delta: 1920),
            MIDIBuilder.timeSignature(3, 4, delta: 0)
        ])
        let file = try MIDIReader.read(data)

        XCTAssertEqual(file.timeSignatures.count, 2)
        XCTAssertNil(file.bars, "a file that changes metre has no single bar count")
        XCTAssertGreaterThan(file.beats, 0, "beats are still well defined")
    }

    func testNonStandardDivisionStillConverts() throws {
        let data = MIDIBuilder.file([MIDIBuilder.tempo(bpm: 120)]
                                    + MIDIBuilder.note(60, at: 0, length: 96),
                                    division: 96)
        let file = try MIDIReader.read(data)
        XCTAssertEqual(file.division.ticksPerQuarterNote, 96)
        XCTAssertEqual(file.notes.first?.durationSeconds ?? 0, 0.5, accuracy: 0.001)
    }

    /// SMPTE division is absolute time and does not involve tempo at all. No file in the
    /// measured corpus used it, which is exactly why it needs a test rather than an assumption.
    func testSMPTEDivisionIsAbsoluteTime() throws {
        // 25 frames per second, 40 ticks per frame — 1,000 ticks per second.
        let raw = UInt16(bitPattern: Int16(Int8(-25)) << 8) | 40
        let data = MIDIBuilder.file(MIDIBuilder.note(60, at: 0, length: 500), division: raw)
        let file = try MIDIReader.read(data)

        guard case .smpte(let fps, let ticks) = file.division else {
            return XCTFail("expected SMPTE division, got \(file.division)")
        }
        XCTAssertEqual(fps, 25)
        XCTAssertEqual(ticks, 40)
        XCTAssertEqual(file.division.ticksPerSecond ?? 0, 1000, accuracy: 0.001)
        XCTAssertEqual(file.notes.first?.durationSeconds ?? 0, 0.5, accuracy: 0.001)
    }
}
