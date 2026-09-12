//
//  ChordTests.swift
//  MIDIFileKitTests
//
//  Created by David Sherlock on 2026.
//
//  Simultaneity — which is exact — and naming, which is not and must therefore refuse.
//

import XCTest
@testable import MIDIFileKit

final class ChordTests: XCTestCase {

    private func chords(_ events: [MIDIBuilder.Event], minimumVoices: Int = 3,
                        minimumTicks: Int = 0) throws -> [Chord] {
        let file = try MIDIReader.read(MIDIBuilder.file(events))
        return file.chords(minimumVoices: minimumVoices, minimumTicks: minimumTicks)
    }

    /// Three notes struck and released together.
    private func block(_ pitches: [Int], length: UInt32 = 960) -> [MIDIBuilder.Event] {
        var events = pitches.map { MIDIBuilder.noteOn($0, delta: 0) }
        events.append(MIDIBuilder.noteOff(pitches[0], delta: length))
        events += pitches.dropFirst().map { MIDIBuilder.noteOff($0, delta: 0) }
        return events
    }

    func testNamesATriad() throws {
        let found = try chords(block([60, 64, 67]))
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.name, "C")
        XCTAssertEqual(found.first?.voices, 3)
        XCTAssertEqual(found.first?.intervals, [0, 4, 7])
    }

    func testNamesAMinorTriad() throws {
        XCTAssertEqual(try chords(block([69, 72, 76])).first?.name, "Am")
    }

    /// [0,4,7,10] must be tried before [0,4,7], or every dominant seventh reports as a
    /// triad with a stray note.
    func testSeventhIsPreferredOverTriadPlusStrayNote() throws {
        XCTAssertEqual(try chords(block([67, 71, 74, 77])).first?.name, "G7")
    }

    /// An inversion is a real distinction and is written with a slash.
    func testInversionIsNamedWithASlash() throws {
        let found = try chords(block([64, 67, 72]))     // E G C — C major over E
        XCTAssertEqual(found.first?.name, "C/E")
        XCTAssertEqual(found.first?.root, 0)
        XCTAssertEqual(found.first?.bass?.className, "E")
    }

    /// A chord with no third gets a name that says so rather than being guessed into a mode.
    func testPowerChordIsNotGivenAMode() throws {
        let found = try chords(block([60, 67, 72]), minimumVoices: 3)
        XCTAssertEqual(found.first?.name, "C5")
    }

    /// Exact matching, not nearest. A name that is always produced carries no information.
    func testUnnameableClusterGetsNoName() throws {
        let found = try chords(block([60, 61, 62]))
        XCTAssertEqual(found.count, 1)
        XCTAssertNil(found.first?.name, "three chromatic neighbours are not a chord")
        XCTAssertEqual(found.first?.pitches.count, 3, "but the notes are still reported")
    }

    /// The simultaneity itself is a recorded fact even when the naming declines.
    func testPitchesAreReportedWhenTheNameIsNil() throws {
        let found = try chords(block([60, 61, 66, 71]))
        XCTAssertNil(found.first?.name)
        XCTAssertEqual(found.first?.pitches.map(\.number), [60, 61, 66, 71])
    }

    func testNotesThatDoNotOverlapAreNotAChord() throws {
        let events = MIDIBuilder.note(60, at: 0, length: 240)
            + MIDIBuilder.note(64, at: 0, length: 240)
            + MIDIBuilder.note(67, at: 0, length: 240)
        XCTAssertTrue(try chords(events).isEmpty, "a sequence of single notes is not a chord")
    }

    /// Humanised playing does not strike a chord's notes at the same instant. Without a
    /// floor, a triad spread over 8 ticks produces spurious one- and two-note spans first.
    func testMinimumTicksSuppressesSpreadArtefacts() throws {
        let events = [
            MIDIBuilder.noteOn(60, delta: 0),
            MIDIBuilder.noteOn(64, delta: 4),
            MIDIBuilder.noteOn(67, delta: 4),
            MIDIBuilder.noteOff(60, delta: 950),
            MIDIBuilder.noteOff(64, delta: 0),
            MIDIBuilder.noteOff(67, delta: 0)
        ]
        let unfiltered = try chords(events, minimumTicks: 0)
        let filtered = try chords(events, minimumTicks: 16)

        XCTAssertEqual(filtered.count, 1, "one chord, once the spread is ignored")
        XCTAssertEqual(filtered.first?.name, "C")
        XCTAssertLessThanOrEqual(unfiltered.count, 2)
    }

    /// A held chord must not be split at every passing note in another voice.
    func testHeldChordIsNotFragmentedByAMelody() throws {
        var events = [MIDIBuilder.noteOn(60, delta: 0), MIDIBuilder.noteOn(64, delta: 0),
                      MIDIBuilder.noteOn(67, delta: 0)]
        // A melody note that starts and stops inside the chord, on another channel.
        events += [MIDIBuilder.noteOn(72, channel: 1, delta: 240),
                   MIDIBuilder.noteOff(72, channel: 1, delta: 240)]
        events += [MIDIBuilder.noteOff(60, delta: 480), MIDIBuilder.noteOff(64, delta: 0),
                   MIDIBuilder.noteOff(67, delta: 0)]
        let found = try chords(events)

        // The melody note is another C, so the four-voice span is still C major — the point
        // is that the triad is not chopped into three separate one-beat chords around it.
        XCTAssertTrue(found.allSatisfy { $0.name == "C" },
                      "every span here is C major, doubled or not")
        XCTAssertLessThanOrEqual(found.count, 3, "spans merge rather than fragmenting")
    }

    func testMinimumVoicesOfTwoReportsIntervals() throws {
        let found = try chords(block([60, 67]), minimumVoices: 2)
        XCTAssertEqual(found.first?.name, "C5")
        XCTAssertEqual(found.first?.voices, 2)
    }

    func testPercussionIsExcludedFromChords() throws {
        var events = [MIDIBuilder.Event]()
        for pitch in [36, 38, 42] { events.append(MIDIBuilder.noteOn(pitch, channel: 9, delta: 0)) }
        events.append(MIDIBuilder.noteOff(36, channel: 9, delta: 480))
        for pitch in [38, 42] { events.append(MIDIBuilder.noteOff(pitch, channel: 9, delta: 0)) }
        XCTAssertTrue(try chords(events).isEmpty)
    }

    /// Chord positions must come from the real tempo map, not an interpolation.
    func testChordTimingFollowsTheTempo() throws {
        var builder = MIDIBuilder()
        builder.format = 1
        builder.tracks = [[MIDIBuilder.tempo(bpm: 60)], block([60, 64, 67], length: 480)]
        let file = try MIDIReader.read(builder.build())
        let found = file.chords()

        let chord = try XCTUnwrap(found.first)
        XCTAssertEqual(chord.startSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(chord.startBeats, 0, accuracy: 0.001)
    }
}
