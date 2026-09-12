//
//  InstrumentTests.swift
//  MIDIFileKitTests
//
//  Created by David Sherlock on 2026.
//
//  Multi-channel, multi-instrument files — a full arrangement rather than a loop.
//
//  FIXTURE-VERIFIED, NOT CORPUS-VERIFIED, and that distinction is the reason this file says
//  so out loud. The 6,013-file corpus the rest of the library was measured against is loop
//  packs: 4 files use more than one channel and NOT ONE contains a program change. So none
//  of the behaviour below is backed by real-world measurement the way the key and chord
//  thresholds are — it is built to the General MIDI specification and tested against
//  hand-assembled bytes. If a real arrangement ever contradicts it, the file is right.
//

import XCTest
@testable import MIDIFileKit

final class InstrumentTests: XCTestCase {

    /// A small arrangement: piano, fretless bass, strings, and a drum kit on channel 10.
    private func arrangement() throws -> MIDIFile {
        var builder = MIDIBuilder()
        builder.format = 1
        builder.tracks = [
            [MIDIBuilder.trackName("Conductor"), MIDIBuilder.tempo(bpm: 96),
             MIDIBuilder.timeSignature(4, 4)],
            [MIDIBuilder.trackName("Piano"), MIDIBuilder.programChange(0, channel: 0)]
                + MIDIBuilder.note(60, at: 0, length: 480, channel: 0)
                + MIDIBuilder.note(64, at: 0, length: 480, channel: 0),
            [MIDIBuilder.trackName("Bass"), MIDIBuilder.programChange(35, channel: 1)]
                + MIDIBuilder.note(40, at: 0, length: 960, channel: 1),
            [MIDIBuilder.trackName("Strings"), MIDIBuilder.programChange(48, channel: 2)]
                + MIDIBuilder.note(72, at: 0, length: 1920, channel: 2),
            [MIDIBuilder.trackName("Drums"), MIDIBuilder.programChange(0, channel: 9)]
                + MIDIBuilder.note(36, at: 0, length: 120, channel: 9)
                + MIDIBuilder.note(38, at: 240, length: 120, channel: 9)
        ]
        return try MIDIReader.read(builder.build())
    }

    func testEveryChannelIsReportedWithItsInstrument() throws {
        let file = try arrangement()
        XCTAssertTrue(file.isMultiChannel)

        let channels = file.channels
        XCTAssertEqual(channels.map(\.number), [0, 1, 2, 9])
        XCTAssertEqual(channels.map(\.label),
                       ["Acoustic Grand Piano", "Fretless Bass", "String Ensemble 1", "Standard Kit"])
        XCTAssertEqual(channels.map(\.noteCount), [2, 1, 1, 2])
    }

    func testGeneralMIDIFamiliesAreNamed() throws {
        let file = try arrangement()
        let families = file.channels.compactMap(\.instruments.first?.family)
        // Program 48 is "String Ensemble 1", which General MIDI files under Ensemble, not
        // Strings — Strings is 40-47, the solo instruments. The spec's grouping wins over
        // the intuitive one.
        XCTAssertEqual(families, ["Piano", "Bass", "Ensemble", "Drum Kit"])
    }

    /// On channel 10 the program number selects a kit, not an instrument — calling program 0
    /// "Acoustic Grand Piano" there would be wrong in a way that reads as plausible.
    func testChannelTenIsADrumKitNotAnInstrument() throws {
        let file = try arrangement()
        let drums = try XCTUnwrap(file.channels.first { $0.number == 9 })

        XCTAssertTrue(drums.isPercussion)
        XCTAssertEqual(drums.instruments.first?.name, "Standard Kit")
        XCTAssertEqual(drums.instruments.first?.family, "Drum Kit")
        XCTAssertTrue(drums.instruments.first?.isDrumKit == true)
        XCTAssertEqual(Instrument(atTicks: 0, channel: 9, program: 25).name, "TR-808 Kit")
    }

    /// The loop-library case: no program changes anywhere, so the track name is the only
    /// thing that names the part, and it must be used rather than yielding "Channel 1".
    func testTrackNameIsUsedWhenThereIsNoProgramChange() throws {
        var builder = MIDIBuilder()
        builder.format = 1
        builder.tracks = [[MIDIBuilder.trackName("Massive 1")]
                          + MIDIBuilder.note(45, at: 0, length: 480)]
        let file = try MIDIReader.read(builder.build())

        XCTAssertTrue(file.instruments.isEmpty)
        XCTAssertEqual(file.channels.first?.label, "Massive 1")
    }

    func testUnnamedChannelFallsBackToItsNumber() throws {
        let file = try MIDIReader.read(MIDIBuilder.file(
            MIDIBuilder.note(60, at: 0, length: 480, channel: 3)))
        XCTAssertEqual(file.channels.first?.label, "Channel 4", "channels are 1-based to people")
    }

    /// A channel that switches instrument mid-piece has several programs, and reporting only
    /// the first would misname everything after the change.
    func testAChannelThatChangesInstrumentKeepsBoth() throws {
        let data = MIDIBuilder.file([MIDIBuilder.programChange(0)]
                                    + MIDIBuilder.note(60, at: 0, length: 480)
                                    + [MIDIBuilder.programChange(48, delta: 0)]
                                    + MIDIBuilder.note(64, at: 0, length: 480))
        let file = try MIDIReader.read(data)

        XCTAssertEqual(file.instruments.count, 2)
        XCTAssertEqual(file.instruments.map(\.name), ["Acoustic Grand Piano", "String Ensemble 1"])
        XCTAssertEqual(file.channels.first?.instruments.count, 2)
    }

    /// Program change and channel pressure carry ONE data byte where every other channel
    /// voice message carries two. Sizing them wrong desynchronises the rest of the track.
    func testOneDataByteEventsAreSizedCorrectly() throws {
        let data = MIDIBuilder.file([
            MIDIBuilder.programChange(42),
            MIDIBuilder.channelPressure(64),
            MIDIBuilder.noteOn(60, delta: 0),
            MIDIBuilder.noteOff(60, delta: 480)
        ])
        let file = try MIDIReader.read(data)

        XCTAssertEqual(file.notes.count, 1, "a mis-sized event would eat the note-on")
        XCTAssertEqual(file.notes.first?.durationTicks, 480)
        XCTAssertEqual(file.instruments.first?.program, 42)
    }

    /// Control changes and pitch bend are not modelled, but they must be stepped over
    /// cleanly — the commonest thing between notes in a real arrangement.
    func testControllersAndBendsAreSkippedWithoutDisturbingNotes() throws {
        let data = MIDIBuilder.file([
            MIDIBuilder.controlChange(7, 100),
            MIDIBuilder.noteOn(60, delta: 0),
            MIDIBuilder.pitchBend(8192, delta: 120),
            MIDIBuilder.controlChange(1, 64, delta: 0),
            MIDIBuilder.noteOff(60, delta: 360)
        ])
        let file = try MIDIReader.read(data)

        XCTAssertEqual(file.notes.count, 1)
        XCTAssertEqual(file.notes.first?.durationTicks, 480)
    }

    /// Per-channel ranges are what tell a reader which part is the bass without guessing.
    func testChannelRangesAreReported() throws {
        let file = try arrangement()
        let bass = try XCTUnwrap(file.channels.first { $0.number == 1 })
        let strings = try XCTUnwrap(file.channels.first { $0.number == 2 })

        XCTAssertEqual(bass.range?.lowerBound.name, "E2")
        XCTAssertEqual(strings.range?.lowerBound.name, "C5")
        XCTAssertLessThan(bass.range!.lowerBound, strings.range!.lowerBound)
    }

    /// The whole General MIDI table must be addressable without falling off either end.
    func testEveryGeneralMIDIProgramHasANameAndFamily() {
        XCTAssertEqual(Instrument.generalMIDINames.count, 128)
        for program in 0 ..< 128 {
            let instrument = Instrument(atTicks: 0, channel: 0, program: program)
            XCTAssertFalse(instrument.name.isEmpty)
            XCTAssertTrue(Instrument.families.contains(instrument.family))
        }
    }

    /// Analysis must still work on an arrangement: percussion excluded, the rest pooled.
    func testKeyAndChordsWorkAcrossChannels() throws {
        let file = try arrangement()
        let key = try XCTUnwrap(file.estimatedKey)
        XCTAssertFalse(key.weights.isEmpty)
        // C and E from the pitched parts; the drum channel's 36 and 38 must not appear or
        // there would be four pitch classes here.
        XCTAssertEqual(key.distinctPitchClasses, 2, "percussion is excluded from the profile")
        XCTAssertEqual(key.rootName, "C")
        XCTAssertEqual(key.mode, .major, "E is a major third above C, so the mode is settled")
        XCTAssertFalse(key.isWellSupported, "two pitch classes is still too thin to rely on")
    }
}
