//
//  RobustnessTests.swift
//  MIDIFileKitTests
//
//  Created by David Sherlock on 2026.
//
//  Broken input. A reader pointed at a scraped corpus meets all of this, and the requirement
//  is to fail with a usable error or salvage what is there — never to hang, trap or invent.
//

import XCTest
@testable import MIDIFileKit

final class RobustnessTests: XCTestCase {

    func testEmptyDataIsNotAMIDIFile() {
        XCTAssertThrowsError(try MIDIReader.read(Data())) { error in
            XCTAssertEqual(error as? MIDIFileError, .truncated(at: 0))
        }
    }

    /// The usual cause is a renamed audio file or a RIFF-wrapped .rmi, and the four bytes
    /// say which — so the error carries them.
    func testNonMIDIDataNamesWhatItFound() {
        let wav = Data([UInt8]("RIFF".utf8) + [0, 0, 0, 0] + [UInt8]("WAVE".utf8))
        XCTAssertThrowsError(try MIDIReader.read(wav)) { error in
            XCTAssertEqual(error as? MIDIFileError, .notAMIDIFile(found: "RIFF"))
        }
    }

    func testUnsupportedFormatIsRejected() {
        var bytes = [UInt8]("MThd".utf8) + [0, 0, 0, 6]
        bytes += [0, 9]          // format 9 — no such thing
        bytes += [0, 1, 1, 224]
        XCTAssertThrowsError(try MIDIReader.read(Data(bytes))) { error in
            XCTAssertEqual(error as? MIDIFileError, .unsupportedFormat(9))
        }
    }

    func testZeroDivisionIsRejected() {
        let bytes = [UInt8]("MThd".utf8) + [0, 0, 0, 6] + [0, 0, 0, 1, 0, 0]
        XCTAssertThrowsError(try MIDIReader.read(Data(bytes))) { error in
            XCTAssertEqual(error as? MIDIFileError, .invalidDivision)
        }
    }

    /// A header longer than six bytes is allowed to grow; the length field is how a reader
    /// skips what it does not understand.
    func testOversizedHeaderIsSkipped() throws {
        var bytes = [UInt8]("MThd".utf8) + [0, 0, 0, 10]
        bytes += [0, 0, 0, 1, 1, 224] + [9, 9, 9, 9]
        let track = [UInt8](MIDIBuilder.file(MIDIBuilder.note(60, at: 0, length: 480)))
        bytes += track[14...]
        let file = try MIDIReader.read(Data(bytes))
        XCTAssertEqual(file.notes.count, 1)
    }

    /// Running status with nothing to run from is corruption, and it must be reported rather
    /// than read as a note.
    func testRunningStatusWithoutAStatusThrows() {
        var body: [UInt8] = [0x00, 0x3C, 0x40]           // delta, then data with no status
        var bytes = [UInt8]("MThd".utf8) + [0, 0, 0, 6] + [0, 0, 0, 1, 1, 224]
        bytes += [UInt8]("MTrk".utf8) + [0, 0, 0, UInt8(body.count)] + body
        body = []
        XCTAssertThrowsError(try MIDIReader.read(Data(bytes))) { error in
            guard case .runningStatusWithoutStatus = (error as? MIDIFileError) else {
                return XCTFail("expected a running-status error, got \(error)")
            }
        }
    }

    /// A variable-length quantity with the continuation bit set in every byte would, without
    /// the four-byte cap, walk the whole track building a meaningless integer.
    func testUnterminatedVariableLengthQuantityIsRejected() {
        var reader = ByteReader([0x80, 0x80, 0x80, 0x80, 0x80, 0x00])
        XCTAssertThrowsError(try VariableLengthQuantity.read(from: &reader, track: 0))
    }

    func testVariableLengthRoundTripsThroughBothImplementations() throws {
        // The encoder in MIDIBuilder and the decoder in the reader must agree, since every
        // fixture in this suite depends on it.
        for value in [UInt32(0), 1, 127, 128, 255, 8192, 16383, 16384, 0x0FFFFFFF] {
            var reader = ByteReader(VariableLengthQuantity.encode(value))
            XCTAssertEqual(try VariableLengthQuantity.read(from: &reader, track: 0), value)
            XCTAssertTrue(reader.isAtEnd, "\(value) should consume exactly its own bytes")
        }
    }

    /// A track whose declared length runs past the end of the file. Scraped corpora are full
    /// of these, and a file that is 99% intact is worth reading.
    func testTruncatedFinalTrackIsSalvaged() throws {
        var bytes = [UInt8](MIDIBuilder.file(
            MIDIBuilder.note(60, at: 0, length: 480) + MIDIBuilder.note(64, at: 0, length: 480)))
        bytes.removeLast(4)
        let file = try MIDIReader.read(Data(bytes))
        XCTAssertGreaterThanOrEqual(file.notes.count, 1, "salvage what survived")
    }

    /// A header that claims more tracks than the file contains. The chunks are the truth.
    func testDeclaredTrackCountIsAdvisoryOnly() throws {
        var bytes = [UInt8](MIDIBuilder.file(MIDIBuilder.note(60, at: 0, length: 480)))
        bytes[11] = 7                       // claim seven tracks, supply one
        let file = try MIDIReader.read(Data(bytes))
        XCTAssertEqual(file.tracks.count, 1)
        XCTAssertEqual(file.notes.count, 1)
    }

    func testNoteNumbersAreClampedToTheValidRange() {
        XCTAssertEqual(Pitch(-5).number, 0)
        XCTAssertEqual(Pitch(300).number, 127)
        XCTAssertEqual(Pitch(60).name, "C4")
        XCTAssertEqual(Pitch(69).frequency, 440, accuracy: 0.001)
    }

    /// Meta text is nominally ASCII and is in practice whatever the DAW's locale produced.
    func testInvalidUTF8InATrackNameSurvivesAsText() throws {
        let raw: [UInt8] = [0xFF, 0x03, 0x04, 0x42, 0x61, 0xF8, 0x73]      // "Ba<F8>s"
        let data = MIDIBuilder.file([MIDIBuilder.Event(delta: 0, bytes: raw)]
                                    + MIDIBuilder.note(60, at: 0, length: 480))
        let file = try MIDIReader.read(data)
        XCTAssertNotNil(file.tracks.first?.name)
        XCTAssertFalse(file.tracks.first?.name?.isEmpty ?? true)
    }

    func testFileWithNoNotesParsesAndReportsNothing() throws {
        let file = try MIDIReader.read(MIDIBuilder.file([MIDIBuilder.trackName("empty")]))
        XCTAssertTrue(file.notes.isEmpty)
        XCTAssertNil(file.estimatedKey)
        XCTAssertTrue(file.chords().isEmpty)
        XCTAssertEqual(file.duration, 0)
    }

    func testFileRoundTripsThroughJSON() throws {
        let original = try MIDIReader.read(MIDIBuilder.file(
            [MIDIBuilder.trackName("Bass"), MIDIBuilder.tempo(bpm: 138),
             MIDIBuilder.marker("drop")] + MIDIBuilder.note(45, at: 0, length: 960)))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MIDIFile.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.markers.first?.text, "drop")
        XCTAssertEqual(decoded.tempoMap.initial.bpm, original.tempoMap.initial.bpm, accuracy: 0.01)
    }
}
