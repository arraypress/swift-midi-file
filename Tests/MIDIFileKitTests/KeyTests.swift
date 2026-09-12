//
//  KeyTests.swift
//  MIDIFileKitTests
//
//  Created by David Sherlock on 2026.
//
//  The key estimator — and above all the cases where it must REFUSE to name a mode.
//

import XCTest
@testable import MIDIFileKit

final class KeyTests: XCTestCase {

    /// Build a file from pitch classes played as equal-length notes in octave 4.
    private func key(of pitches: [Int], durations: [UInt32]? = nil) throws -> KeyEstimate {
        var events: [MIDIBuilder.Event] = []
        for (index, pitch) in pitches.enumerated() {
            let length = durations?[index] ?? 480
            events += [MIDIBuilder.noteOn(pitch, delta: 0), MIDIBuilder.noteOff(pitch, delta: length)]
        }
        let file = try MIDIReader.read(MIDIBuilder.file(events))
        return try XCTUnwrap(file.estimatedKey)
    }

    func testFindsCMajorFromItsScale() throws {
        let estimate = try key(of: [60, 62, 64, 65, 67, 69, 71, 72])
        XCTAssertEqual(estimate.rootName, "C")
        XCTAssertEqual(estimate.mode, .major)
        XCTAssertEqual(estimate.name, "C")
        XCTAssertTrue(estimate.hasThird)
        XCTAssertTrue(estimate.isWellSupported)
    }

    func testFindsAMinorFromItsScale() throws {
        // The same seven pitch classes as C major. Only the emphasis separates them, which is
        // what the profile correlation is for — and why a longer tonic matters.
        let estimate = try key(of: [57, 57, 59, 60, 62, 64, 65, 67, 57],
                               durations: [960, 960, 240, 480, 240, 480, 240, 240, 960])
        XCTAssertEqual(estimate.rootName, "A")
        XCTAssertEqual(estimate.mode, .minor)
        XCTAssertEqual(estimate.name, "Am")
    }

    /// THE CENTRAL CASE. A root and a fifth belong to both a major and a minor key. The file
    /// does not say which, so neither does the library.
    func testRefusesAModeWithNoThird() throws {
        let estimate = try key(of: [62, 69, 62, 69, 74])      // D and A only
        XCTAssertEqual(estimate.rootName, "D")
        XCTAssertNil(estimate.mode, "no third is present, so no mode can be claimed")
        XCTAssertFalse(estimate.hasThird)
        XCTAssertEqual(estimate.name, "D", "the name must carry no mode suffix")
        XCTAssertTrue(estimate.summary.contains("undetermined"))
    }

    /// A single repeated note is the extreme of the same case, and the one that occurred in
    /// 19 of 108 labelled files in the corpus.
    func testSingleRepeatedPitchClaimsNoMode() throws {
        let estimate = try key(of: [43, 43, 43, 43, 55, 43])
        XCTAssertNil(estimate.mode)
        XCTAssertEqual(estimate.distinctPitchClasses, 1)
        XCTAssertFalse(estimate.isWellSupported,
                       "one pitch class cannot support a key, whatever the correlation says")
    }

    /// When a third IS present it decides the mode outright, ahead of the profile correlation.
    /// A minor third above the root cannot occur in that root's major key.
    func testMinorThirdDecidesTheMode() throws {
        let estimate = try key(of: [60, 63, 67, 60, 63, 67])   // C Eb G
        XCTAssertEqual(estimate.rootName, "C")
        XCTAssertEqual(estimate.mode, .minor)
        XCTAssertTrue(estimate.hasThird)
    }

    func testMajorThirdDecidesTheMode() throws {
        let estimate = try key(of: [60, 64, 67, 60, 64, 67])   // C E G
        XCTAssertEqual(estimate.rootName, "C")
        XCTAssertEqual(estimate.mode, .major)
    }

    /// Drum parts carry note numbers that are instrument identifiers, not pitches. Letting
    /// them into the profile moves the answer toward whatever the kit numbering spells.
    func testPercussionIsExcluded() throws {
        var events = [MIDIBuilder.Event]()
        for pitch in [60, 64, 67] {
            events += [MIDIBuilder.noteOn(pitch, delta: 0), MIDIBuilder.noteOff(pitch, delta: 960)]
        }
        // A dense kick-snare-hat pattern on channel 9, spelling nothing.
        for pitch in [36, 38, 42, 42, 36, 38, 42, 46] {
            events += [MIDIBuilder.noteOn(pitch, channel: 9, delta: 0),
                       MIDIBuilder.noteOff(pitch, channel: 9, delta: 120)]
        }
        let file = try MIDIReader.read(MIDIBuilder.file(events))
        let estimate = try XCTUnwrap(file.estimatedKey)

        XCTAssertEqual(estimate.name, "C", "the drum part must not move the key")
        let withDrums = KeyEstimator.estimate(notes: file.notes, includePercussion: true)
        XCTAssertNotNil(withDrums, "including percussion is still allowed, just not the default")
    }

    /// Pooling is the recommended treatment for thin material, and it must actually help.
    ///
    /// The two basslines here are the corpus's common case: root and fifth, no third, so no
    /// mode is claimable from either alone. The chord part carries the third. Pooled — which
    /// is what a folder of one pack's loops amounts to — the mode resolves.
    func testPoolingThinPartsRecoversTheMode() throws {
        func notes(_ pitches: [Int]) throws -> [Note] {
            var events = [MIDIBuilder.Event]()
            for pitch in pitches {
                events += [MIDIBuilder.noteOn(pitch, delta: 0),
                           MIDIBuilder.noteOff(pitch, delta: 480)]
            }
            return try MIDIReader.read(MIDIBuilder.file(events)).notes
        }

        let bassOne = try notes([45, 52, 45, 52])           // A E — root and fifth
        let bassTwo = try notes([45, 57, 52, 45])           // A A E
        let chords  = try notes([48, 52, 45, 48, 52])       // C E A — carries the minor third

        XCTAssertNil(KeyEstimator.estimate(notes: bassOne)?.mode, "root and fifth name no mode")
        XCTAssertNil(KeyEstimator.estimate(notes: bassTwo)?.mode, "root and fifth name no mode")

        let together = try XCTUnwrap(KeyEstimator.estimate(pooling: [bassOne, bassTwo, chords]))
        XCTAssertEqual(together.rootName, "A")
        XCTAssertEqual(together.mode, .minor, "pooled, the third appears and the mode resolves")
        XCTAssertTrue(together.isWellSupported)
    }

    func testEmptyNotesGiveNoEstimate() {
        XCTAssertNil(KeyEstimator.estimate(notes: []))
    }

    /// Correlation of a flat vector is zero, not a crash and not a division by zero.
    func testCorrelationOfAFlatVectorIsZero() {
        let flat = [Double](repeating: 1, count: 12)
        XCTAssertEqual(KeyEstimator.correlate(flat, KeyEstimator.majorProfile), 0)
    }
}
