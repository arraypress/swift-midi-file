//
//  ChordSpellerTests.swift
//  MIDIFileKitTests
//
//  Created by David Sherlock on 2026.
//
//  Spelling a chord name, and the round trip back through the extractor.
//

import XCTest
@testable import MIDIFileKit

final class ChordSpellerTests: XCTestCase {

    private func names(_ chord: String, octave: Int = 3) -> [String]? {
        ChordSpeller.pitches(for: chord, octave: octave)?.map(\.name)
    }

    func testSpellsBasicTriads() {
        XCTAssertEqual(names("C"), ["C3", "E3", "G3"])
        XCTAssertEqual(names("Am"), ["A3", "C4", "E4"])
        XCTAssertEqual(names("F#m"), ["F#3", "A3", "C#4"])
    }

    func testSpellsExtendedChords() {
        XCTAssertEqual(names("Cmaj7"), ["C3", "E3", "G3", "B3"])
        XCTAssertEqual(names("G7"), ["G3", "B3", "D4", "F4"])
        XCTAssertEqual(names("Am9"), ["A3", "B3", "C4", "E4", "G4"])
    }

    func testSpellsSuspensionsAndPowerChords() {
        XCTAssertEqual(names("Dsus4"), ["D3", "G3", "A3"])
        XCTAssertEqual(names("Esus2"), ["E3", "F#3", "B3"])
        XCTAssertEqual(names("A5"), ["A3", "E4"])
    }

    /// Flats are accepted on input even though the library spells with sharps.
    func testFlatsAreAcceptedOnInput() {
        XCTAssertEqual(names("Bbmaj7"), names("A#maj7"))
        XCTAssertEqual(names("Eb"), ["D#3", "G3", "A#3"])
    }

    /// An inversion puts the named note underneath without adding a voice.
    func testInversionPutsTheBassUnderneath() {
        let pitches = try? XCTUnwrap(ChordSpeller.pitches(for: "C/E", octave: 3))
        XCTAssertEqual(pitches?.map(\.name), ["E2", "C3", "G3"])
        XCTAssertEqual(pitches?.count, 3, "an inversion must not add a fourth voice")
    }

    func testOctaveMovesTheWholeChord() {
        XCTAssertEqual(names("C", octave: 2), ["C2", "E2", "G2"])
        XCTAssertEqual(names("C", octave: 5), ["C5", "E5", "G5"])
    }

    func testUnknownNamesAreRefused() {
        XCTAssertNil(ChordSpeller.pitches(for: "Hm7"), "no such root")
        XCTAssertNil(ChordSpeller.pitches(for: "Cwobble"), "no such quality")
        XCTAssertNil(ChordSpeller.pitches(for: ""))
        XCTAssertNil(ChordSpeller.pitches(for: "   "))
    }

    func testOutOfRangeOctavesDoNotCrash() {
        XCTAssertNil(ChordSpeller.pitches(for: "C", octave: 12))
        XCTAssertNotNil(ChordSpeller.pitches(for: "C", octave: -1))
    }

    /// THE ONE THAT MATTERS. Speller and extractor share one quality table, so a name this
    /// produces must be a name that reads back — in every quality, in every root. If a
    /// quality is added to the table and only one direction handles it, this fails.
    func testEveryQualityInEveryRootSurvivesTheRoundTrip() {
        var checked = 0
        for quality in ChordExtractor.qualities {
            for root in 0 ..< 12 {
                let name = Pitch.classNames[root] + quality.name
                guard let pitches = ChordSpeller.pitches(for: name, octave: 3) else {
                    XCTFail("could not spell \(name)")
                    continue
                }
                guard let read = ChordExtractor.name(pitches) else {
                    XCTFail("\(name) spelled as \(pitches.map(\.name)) but named nothing")
                    continue
                }
                XCTAssertEqual(read.label, name, "\(name) read back as \(read.label)")
                checked += 1
            }
        }
        XCTAssertEqual(checked, ChordExtractor.qualities.count * 12)
    }

    /// Spelled chords must also survive being written to a file and read back.
    func testSpelledChordsSurviveAFileRoundTrip() throws {
        var song = Composition(bpm: 120)
        let wanted = ["F#m9", "Dmaj7", "Aadd9", "Esus4"]
        song.addTrack(name: "Pad", channel: 0) { track in
            for (index, chord) in wanted.enumerated() {
                guard let pitches = ChordSpeller.pitches(for: chord, octave: 3) else { continue }
                for pitch in pitches {
                    track.note(pitch.number, atBeat: Double(index) * 4, lasting: 4)
                }
            }
        }
        let reread = try MIDIReader.read(try song.build().data())
        XCTAssertEqual(reread.chords(minimumTicks: 8).compactMap(\.name), wanted)
    }
}
