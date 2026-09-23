//
//  MIDIWriter.swift
//  MIDIFileKit
//
//  Created by David Sherlock on 2026.
//
//  Bytes out: a ``MIDIFile`` back to a Standard MIDI File.
//
//  Writing is much easier than reading, and the reason is worth stating so nobody "optimises"
//  it later. Every ambiguity a reader has to survive — running status, note-off spelled as a
//  zero-velocity note-on, events that imply their own length — exists because the format was
//  designed to fit down a 31,250-baud cable in 1983. A writer has no cable and no reason to
//  economise, so this one always emits a full status byte and a real 0x80 note-off. The output
//  is larger than a DAW's by a few percent and unambiguous to every reader, including the
//  careless ones.
//
//  The round trip is a test, not a hope: ``WriterTests`` writes a file, reads it back and
//  asserts the notes survive — which exercises the reader as much as the writer, since the two
//  share no code.
//

import Foundation

/// Writes Standard MIDI Files.
public enum MIDIWriter {

    /// Serialise a file to bytes.
    ///
    /// Emits format 1 when there is more than one track and format 0 when there is one, which
    /// is what every DAW expects. Meta events that belong to the file rather than to a part —
    /// tempo, time signature, key signature, markers — are written to the FIRST track, because
    /// format 1 defines track 0 as the tempo map and readers that ignore that convention still
    /// find them.
    ///
    /// - Parameter file: any ``MIDIFile``, whether read from disk or built in code.
    /// - Throws: ``MIDIFileError/invalidDivision`` under SMPTE division, which this does not
    ///   yet write — see ``data(for:)`` discussion.
    public static func data(for file: MIDIFile) throws -> Data {
        guard let ticksPerQuarterNote = file.division.ticksPerQuarterNote else {
            // Refused rather than silently written as ticks-per-quarter-note, which would
            // produce a file whose every timestamp means something other than intended.
            throw MIDIFileError.invalidDivision
        }

        var tracks: [[UInt8]] = []
        let sourceTracks = file.tracks.isEmpty ? [Track(index: 0, name: nil, instrument: nil,
                                                        notes: [])] : file.tracks

        for (index, track) in sourceTracks.enumerated() {
            var events: [(tick: Int, order: Int, bytes: [UInt8])] = []

            if let name = track.name, !name.isEmpty {
                events.append((0, 0, meta(0x03, text: name)))
            }
            if let instrument = track.instrument, !instrument.isEmpty {
                events.append((0, 0, meta(0x04, text: instrument)))
            }

            // File-wide events go on the first track.
            if index == 0 {
                for tempo in file.tempoMap.tempos {
                    let micros = tempo.microsecondsPerQuarterNote
                    events.append((tempo.atTicks, -3, [0xFF, 0x51, 0x03,
                                                       UInt8(micros >> 16 & 0xFF),
                                                       UInt8(micros >> 8 & 0xFF),
                                                       UInt8(micros & 0xFF)]))
                }
                for signature in file.timeSignatures {
                    let power = UInt8(max(0, Int(log2(Double(max(1, signature.denominator))))))
                    events.append((signature.atTicks, -2,
                                   [0xFF, 0x58, 0x04, UInt8(clamping: signature.numerator), power,
                                    UInt8(clamping: signature.clocksPerClick),
                                    UInt8(clamping: signature.thirtySecondsPerQuarter)]))
                }
                for key in file.declaredKeys {
                    events.append((key.atTicks, -1,
                                   [0xFF, 0x59, 0x02,
                                    UInt8(bitPattern: Int8(clamping: key.accidentals)),
                                    key.mode == .minor ? 1 : 0]))
                }
                for marker in file.markers {
                    events.append((marker.atTicks, 1, meta(0x06, text: marker.text)))
                }
                for text in file.texts {
                    events.append((text.atTicks, 1, meta(0x01, text: text.text)))
                }
            }

            for instrument in file.instruments where trackOwns(instrument, track: track, index: index) {
                events.append((instrument.atTicks, 2,
                               [0xC0 | UInt8(instrument.channel & 0x0F),
                                UInt8(clamping: instrument.program) & 0x7F]))
            }

            // Control changes at a tick go before that tick's note-offs and note-ons, so a
            // pedal lifted and a note struck on the same beat read back in that order.
            for change in file.controlChanges where trackOwnsChannel(change.channel, track: track, index: index) {
                events.append((change.atTicks, 2,
                               [0xB0 | UInt8(change.channel & 0x0F),
                                UInt8(clamping: change.controller) & 0x7F, UInt8(clamping: change.value) & 0x7F]))
            }

            for note in track.notes {
                let channel = UInt8(note.channel & 0x0F)
                // A ZERO-LENGTH NOTE IS WIDENED TO ONE TICK, and this is not cosmetic. Releases
                // are ordered before strikes at the same tick (below), which is correct when one
                // note ends as another begins — but for a note whose start and end are the SAME
                // tick it would emit that note's own off before its own on. The reader then has
                // an unmatched off and an open on, pairs that on with the NEXT note's off, and
                // every duration in the rest of the track shifts. Measured on the corpus: four
                // files, all acid lines with zero-length notes, every duration after the first
                // one wrong. One tick is inaudible and survives the round trip intact.
                let end = max(note.endTicks, note.startTicks + 1)
                events.append((note.startTicks, 4,
                               [0x90 | channel, UInt8(note.pitch.number),
                                UInt8(clamping: max(1, note.velocity)) & 0x7F]))
                // Note-off ordered BEFORE any note-on at the same tick, so a part that
                // releases one note and strikes the next on the same beat does not read back
                // as two notes overlapping by zero ticks.
                events.append((end, 3, [0x80 | channel, UInt8(note.pitch.number), 0]))
            }

            events.sort { ($0.tick, $0.order) < ($1.tick, $1.order) }

            var body: [UInt8] = []
            var previous = 0
            for event in events {
                body += VariableLengthQuantity.encode(UInt32(max(0, event.tick - previous)))
                body += event.bytes
                previous = event.tick
            }
            body += VariableLengthQuantity.encode(0) + [0xFF, 0x2F, 0x00]
            tracks.append(body)
        }

        var out = [UInt8]("MThd".utf8)
        out += be32(6)
        out += be16(tracks.count > 1 ? 1 : 0)
        out += be16(UInt16(tracks.count))
        out += be16(UInt16(clamping: ticksPerQuarterNote))
        for body in tracks {
            out += [UInt8]("MTrk".utf8)
            out += be32(UInt32(body.count))
            out += body
        }
        return Data(out)
    }

    /// Write a file to disk.
    public static func write(_ file: MIDIFile, to url: URL) throws {
        try data(for: file).write(to: url)
    }

    // MARK: - Private

    /// Which track a program change belongs to when writing.
    ///
    /// A program change carries a channel, not a track, so the mapping back is inferred: it
    /// goes on the track whose notes use that channel. If no track claims the channel it
    /// lands on the first, where a reader will still find it.
    private static func trackOwns(_ instrument: Instrument, track: Track, index: Int) -> Bool {
        trackOwnsChannel(instrument.channel, track: track, index: index)
    }

    private static func trackOwnsChannel(_ channel: Int, track: Track, index: Int) -> Bool {
        if track.notes.contains(where: { $0.channel == channel }) { return true }
        return index == 0 && !track.notes.contains { $0.channel == channel }
            && track.channels.isEmpty
    }

    private static func meta(_ type: UInt8, text: String) -> [UInt8] {
        // Length is a variable-length quantity, not a byte: a track name over 127 characters
        // written with a single length byte corrupts everything after it.
        let raw = [UInt8](text.utf8)
        return [0xFF, type] + VariableLengthQuantity.encode(UInt32(raw.count)) + raw
    }

    private static func be16(_ value: UInt16) -> [UInt8] { [UInt8(value >> 8), UInt8(value & 0xFF)] }
    private static func be32(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF),
         UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }
}

public extension MIDIFile {

    /// Serialise this file to bytes.
    func data() throws -> Data { try MIDIWriter.data(for: self) }

    /// Write this file to disk.
    func write(to url: URL) throws { try MIDIWriter.write(self, to: url) }
}
