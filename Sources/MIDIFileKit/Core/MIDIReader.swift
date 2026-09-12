//
//  MIDIReader.swift
//  MIDIFileKit
//
//  Created by David Sherlock on 2026.
//
//  The parser: bytes in, ``MIDIFile`` out.
//
//  Two details account for most of the bugs a MIDI reader can have, and both are handled
//  explicitly below:
//
//  RUNNING STATUS. An event may omit its status byte, meaning "same as last time". A reader
//  that does not track it reads the first data byte as a status and desynchronises for the
//  rest of the track — producing not an error but a plausible stream of wrong notes. The rule
//  has an edge the specification states and implementations routinely miss: a meta or SysEx
//  event does NOT become the running status, and does not clear it either.
//
//  ZERO-VELOCITY NOTE-ON. Note-off is usually written as a note-on with velocity zero, because
//  it packs better under running status. Both spellings mean the same thing and both are
//  accepted here. Treating velocity 0 as a note that sounds is the classic way to end up with
//  every note in a file lasting until the end of it.
//

import Foundation

/// Reads Standard MIDI Files.
public enum MIDIReader {

    /// Read a file from disk.
    ///
    /// - Parameter url: a `.mid` or `.midi` file.
    /// - Throws: ``MIDIFileError`` if it is not a MIDI file or is structurally broken.
    public static func read(contentsOf url: URL) throws -> MIDIFile {
        try read(Data(contentsOf: url))
    }

    /// Read a file already in memory.
    public static func read(_ data: Data) throws -> MIDIFile {
        var reader = ByteReader([UInt8](data))

        let magic = try reader.fourCC()
        guard magic == "MThd" else {
            throw MIDIFileError.notAMIDIFile(found: magic.isEmpty ? "(empty)" : magic)
        }
        let headerLength = try reader.uint32()
        let format = Int(try reader.uint16())
        let declaredTrackCount = Int(try reader.uint16())
        let division = try Division(raw: try reader.uint16())
        guard (0...2).contains(format) else { throw MIDIFileError.unsupportedFormat(format) }
        // The header is six bytes today; the format reserves the right to grow it, and the
        // length field is how a future reader skips what it does not understand.
        if headerLength > 6 { reader.skip(Int(headerLength) - 6) }

        var tracks: [Track] = []
        var tempos: [Tempo] = []
        var timeSignatures: [TimeSignature] = []
        var declaredKeys: [KeySignature] = []
        var markers: [(atTicks: Int, text: String)] = []
        var texts: [(atTicks: Int, text: String)] = []
        var instruments: [Instrument] = []

        var trackIndex = 0
        while !reader.isAtEnd {
            guard reader.canRead(8) else { break }
            let id = try reader.fourCC()
            let length = Int(try reader.uint32())
            guard id == "MTrk" else {
                // An unknown chunk is skippable by design — the format says so explicitly,
                // and files in the wild carry vendor chunks between tracks.
                reader.skip(length)
                continue
            }
            // A truncated final track is common in scraped corpora; read what is there
            // rather than discarding a file that is 99% intact.
            let body = try reader.take(min(length, reader.remaining))
            let parsed = try parseTrack(body, index: trackIndex, division: division)
            tempos += parsed.tempos
            timeSignatures += parsed.timeSignatures
            declaredKeys += parsed.keys
            markers += parsed.markers
            texts += parsed.texts
            instruments += parsed.instruments
            tracks.append(Track(index: trackIndex, name: parsed.name,
                                instrument: parsed.instrument, notes: parsed.rawNotes))
            trackIndex += 1
        }
        _ = declaredTrackCount   // Advisory only: files disagree with themselves and the chunks win.

        let map = TempoMap(tempos: tempos, division: division)
        // Notes are built with tick positions first, then given beats and seconds once the
        // whole tempo map is known — a tempo change in track 3 governs a note in track 1.
        let timed = tracks.map { track in
            Track(index: track.index, name: track.name, instrument: track.instrument,
                  notes: track.notes.map { note in
                      Note(pitch: note.pitch, velocity: note.velocity, channel: note.channel,
                           track: note.track, startTicks: note.startTicks,
                           durationTicks: note.durationTicks,
                           startBeats: map.beats(atTicks: note.startTicks),
                           durationBeats: map.beats(atTicks: note.durationTicks),
                           startSeconds: map.seconds(atTicks: note.startTicks),
                           durationSeconds: map.seconds(atTicks: note.startTicks + note.durationTicks)
                                          - map.seconds(atTicks: note.startTicks))
                  })
        }

        return MIDIFile(format: format, division: division, tracks: timed, tempoMap: map,
                        timeSignatures: timeSignatures.sorted { $0.atTicks < $1.atTicks },
                        declaredKeys: declaredKeys, markers: markers, texts: texts,
                        instruments: instruments.sorted { $0.atTicks < $1.atTicks })
    }

    // MARK: - One track

    private struct TrackContents {
        var name: String?
        var instrument: String?
        var rawNotes: [Note] = []
        var instruments: [Instrument] = []
        var tempos: [Tempo] = []
        var timeSignatures: [TimeSignature] = []
        var keys: [KeySignature] = []
        var markers: [(atTicks: Int, text: String)] = []
        var texts: [(atTicks: Int, text: String)] = []
    }

    private static func parseTrack(_ body: [UInt8], index: Int,
                                   division: Division) throws -> TrackContents {
        var reader = ByteReader(body)
        var out = TrackContents()
        var tick = 0
        var runningStatus: UInt8?
        // Sounding notes, keyed by channel and pitch. An array of starts rather than one,
        // because a part may strike the same pitch again before releasing the first; pairing
        // oldest-on to next-off is what a synthesiser does.
        var sounding: [Int: [(tick: Int, velocity: Int)]] = [:]

        while !reader.isAtEnd {
            tick += Int(try VariableLengthQuantity.read(from: &reader, track: index))
            guard let next = reader.peek() else { break }

            var status: UInt8
            if next & 0x80 != 0 {
                status = next
                _ = try reader.byte()
                // Meta and SysEx do not participate in running status, either as setter
                // or as terminator — the specification is explicit and readers get it wrong.
                if status < 0xF0 { runningStatus = status }
            } else {
                guard let running = runningStatus else {
                    throw MIDIFileError.runningStatusWithoutStatus(track: index,
                                                                   offset: reader.offset)
                }
                status = running
            }

            switch status {
            case 0xFF:
                let type = try reader.byte()
                let length = Int(try VariableLengthQuantity.read(from: &reader, track: index))
                let payload = try reader.take(min(length, reader.remaining))
                apply(meta: type, payload: payload, at: tick, to: &out)

            case 0xF0, 0xF7:
                let length = Int(try VariableLengthQuantity.read(from: &reader, track: index))
                reader.skip(length)

            default:
                let kind = status & 0xF0
                let channel = Int(status & 0x0F)
                let dataCount = (kind == 0xC0 || kind == 0xD0) ? 1 : 2
                guard reader.canRead(dataCount) else { throw MIDIFileError.truncated(at: reader.offset) }
                let data = try reader.take(dataCount)

                switch kind {
                case 0x90 where data[1] > 0:
                    sounding[key(channel, Int(data[0])), default: []]
                        .append((tick, Int(data[1])))
                case 0x80, 0x90:
                    let k = key(channel, Int(data[0]))
                    if var starts = sounding[k], !starts.isEmpty {
                        let start = starts.removeFirst()
                        sounding[k] = starts.isEmpty ? nil : starts
                        out.rawNotes.append(
                            Note(pitch: Pitch(Int(data[0])), velocity: start.velocity,
                                 channel: channel, track: index, startTicks: start.tick,
                                 durationTicks: max(0, tick - start.tick),
                                 startBeats: 0, durationBeats: 0,
                                 startSeconds: 0, durationSeconds: 0))
                    }
                case 0xC0:
                    // Program change: which General MIDI instrument plays this channel.
                    // Absent from every file in the measured loop corpus and present in
                    // essentially every full arrangement, so it cannot be skipped.
                    out.instruments.append(Instrument(atTicks: tick, channel: channel,
                                                      program: Int(data[0])))
                default:
                    break
                }
            }
        }

        // A note still sounding at the end of the track had no note-off. Rather than drop it,
        // end it at the last tick seen: a file that ends mid-note is common, and discarding
        // the note loses more information than assuming it stopped when the music did.
        for (k, starts) in sounding {
            for start in starts {
                out.rawNotes.append(
                    Note(pitch: Pitch(k & 0x7F), velocity: start.velocity,
                         channel: k >> 7, track: index, startTicks: start.tick,
                         durationTicks: max(0, tick - start.tick),
                         startBeats: 0, durationBeats: 0, startSeconds: 0, durationSeconds: 0))
            }
        }
        out.rawNotes.sort { $0.startTicks < $1.startTicks }
        return out
    }

    private static func key(_ channel: Int, _ pitch: Int) -> Int { channel << 7 | pitch }

    private static func apply(meta type: UInt8, payload: [UInt8], at tick: Int,
                              to out: inout TrackContents) {
        // Meta text is nominally ASCII and is in practice whatever the DAW's locale produced.
        // Latin-1 never fails, so a name with a stray byte survives as a name rather than
        // silently becoming nil.
        func text() -> String {
            if let utf8 = String(bytes: payload, encoding: .utf8) { return utf8 }
            return String(bytes: payload, encoding: .isoLatin1) ?? ""
        }

        switch type {
        case 0x01:
            out.texts.append((tick, text()))
        case 0x03:
            if out.name == nil { out.name = text().trimmingCharacters(in: .whitespaces) }
        case 0x04:
            if out.instrument == nil { out.instrument = text().trimmingCharacters(in: .whitespaces) }
        case 0x06:
            out.markers.append((tick, text()))
        case 0x51 where payload.count == 3:
            let micros = Int(payload[0]) << 16 | Int(payload[1]) << 8 | Int(payload[2])
            if micros > 0 { out.tempos.append(Tempo(atTicks: tick, microsecondsPerQuarterNote: micros)) }
        case 0x58 where payload.count >= 4:
            out.timeSignatures.append(
                TimeSignature(atTicks: tick, numerator: Int(payload[0]),
                              denominator: 1 << Int(payload[1]),
                              clocksPerClick: Int(payload[2]),
                              thirtySecondsPerQuarter: Int(payload[3])))
        case 0x59 where payload.count >= 2:
            let accidentals = Int(Int8(bitPattern: payload[0]))
            guard (-7...7).contains(accidentals) else { break }
            out.keys.append(KeySignature(atTicks: tick, accidentals: accidentals,
                                         mode: payload[1] == 1 ? .minor : .major))
        default:
            break
        }
    }
}
