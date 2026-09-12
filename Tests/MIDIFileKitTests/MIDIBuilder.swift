//
//  MIDIBuilder.swift
//  MIDIFileKitTests
//
//  Created by David Sherlock on 2026.
//
//  Builds MIDI files byte by byte so the reader can be tested against a known answer.
//
//  WRITTEN INDEPENDENTLY OF THE READER ON PURPOSE. It shares no code with
//  ``MIDIReader`` — not the variable-length encoder, not the chunk framing, not the
//  running-status rules. If both were built on one implementation a bug in that
//  implementation would cancel out and every test would pass over broken output. The only
//  shared piece is ``VariableLengthQuantity/encode(_:)``, whose agreement with the reader's
//  decoder is itself asserted in ``VariableLengthTests``.
//

import Foundation
@testable import MIDIFileKit

/// Assembles Standard MIDI File bytes for tests.
struct MIDIBuilder {

    /// One event: ticks since the previous event, then raw bytes.
    struct Event {
        let delta: UInt32
        let bytes: [UInt8]
    }

    var format: UInt16 = 0
    var division: UInt16 = 480
    var tracks: [[Event]] = []

    // MARK: - Events

    static func noteOn(_ pitch: Int, velocity: Int = 100, channel: Int = 0,
                       delta: UInt32 = 0) -> Event {
        Event(delta: delta, bytes: [UInt8(0x90 | channel), UInt8(pitch), UInt8(velocity)])
    }

    static func noteOff(_ pitch: Int, channel: Int = 0, delta: UInt32 = 0) -> Event {
        Event(delta: delta, bytes: [UInt8(0x80 | channel), UInt8(pitch), 0])
    }

    /// A note-off written as a note-on with velocity zero — the packing most files use.
    static func noteOffAsZeroVelocity(_ pitch: Int, channel: Int = 0, delta: UInt32 = 0) -> Event {
        Event(delta: delta, bytes: [UInt8(0x90 | channel), UInt8(pitch), 0])
    }

    /// Data bytes with no status byte, relying on the previous event's status.
    static func runningStatus(_ data: [UInt8], delta: UInt32 = 0) -> Event {
        Event(delta: delta, bytes: data)
    }

    /// A program change — one data byte, which is also the running-status edge case where
    /// an event is two bytes long rather than three.
    static func programChange(_ program: Int, channel: Int = 0, delta: UInt32 = 0) -> Event {
        Event(delta: delta, bytes: [UInt8(0xC0 | channel), UInt8(program)])
    }

    /// Channel aftertouch — the other one-data-byte event, included so the reader's event
    /// sizing is tested rather than assumed.
    static func channelPressure(_ value: Int, channel: Int = 0, delta: UInt32 = 0) -> Event {
        Event(delta: delta, bytes: [UInt8(0xD0 | channel), UInt8(value)])
    }

    /// A control change — three bytes, and the commonest thing between the notes.
    static func controlChange(_ controller: Int, _ value: Int, channel: Int = 0,
                              delta: UInt32 = 0) -> Event {
        Event(delta: delta, bytes: [UInt8(0xB0 | channel), UInt8(controller), UInt8(value)])
    }

    static func pitchBend(_ value: Int, channel: Int = 0, delta: UInt32 = 0) -> Event {
        Event(delta: delta, bytes: [UInt8(0xE0 | channel),
                                    UInt8(value & 0x7F), UInt8((value >> 7) & 0x7F)])
    }

    static func tempo(bpm: Double, delta: UInt32 = 0) -> Event {
        let micros = Int(60_000_000 / bpm)
        return Event(delta: delta, bytes: [0xFF, 0x51, 0x03,
                                           UInt8((micros >> 16) & 0xFF),
                                           UInt8((micros >> 8) & 0xFF),
                                           UInt8(micros & 0xFF)])
    }

    static func timeSignature(_ numerator: Int, _ denominator: Int, delta: UInt32 = 0) -> Event {
        let power = UInt8(log2(Double(denominator)))
        return Event(delta: delta, bytes: [0xFF, 0x58, 0x04, UInt8(numerator), power, 24, 8])
    }

    static func keySignature(accidentals: Int, minor: Bool, delta: UInt32 = 0) -> Event {
        Event(delta: delta, bytes: [0xFF, 0x59, 0x02,
                                    UInt8(bitPattern: Int8(accidentals)), minor ? 1 : 0])
    }

    static func trackName(_ name: String, delta: UInt32 = 0) -> Event {
        let raw = [UInt8](name.utf8)
        return Event(delta: delta, bytes: [0xFF, 0x03, UInt8(raw.count)] + raw)
    }

    static func marker(_ text: String, delta: UInt32 = 0) -> Event {
        let raw = [UInt8](text.utf8)
        return Event(delta: delta, bytes: [0xFF, 0x06, UInt8(raw.count)] + raw)
    }

    static func sysEx(_ payload: [UInt8], delta: UInt32 = 0) -> Event {
        Event(delta: delta, bytes: [0xF0, UInt8(payload.count)] + payload)
    }

    static let endOfTrack = Event(delta: 0, bytes: [0xFF, 0x2F, 0x00])

    // MARK: - Assembly

    /// A note-on, a gap, and a note-off — the common case, spelled once.
    static func note(_ pitch: Int, at start: UInt32, length: UInt32,
                     velocity: Int = 100, channel: Int = 0) -> [Event] {
        [noteOn(pitch, velocity: velocity, channel: channel, delta: start),
         noteOff(pitch, channel: channel, delta: length)]
    }

    func build() -> Data {
        var out: [UInt8] = []
        out += [UInt8]("MThd".utf8)
        out += be32(6)
        out += be16(format)
        out += be16(UInt16(tracks.count))
        out += be16(division)

        for track in tracks {
            var body: [UInt8] = []
            for event in track {
                body += VariableLengthQuantity.encode(event.delta)
                body += event.bytes
            }
            body += VariableLengthQuantity.encode(0) + [0xFF, 0x2F, 0x00]
            out += [UInt8]("MTrk".utf8)
            out += be32(UInt32(body.count))
            out += body
        }
        return Data(out)
    }

    private func be16(_ value: UInt16) -> [UInt8] { [UInt8(value >> 8), UInt8(value & 0xFF)] }
    private func be32(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF),
         UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    /// A one-track file containing exactly these events.
    static func file(_ events: [Event], division: UInt16 = 480, format: UInt16 = 0) -> Data {
        var builder = MIDIBuilder()
        builder.division = division
        builder.format = format
        builder.tracks = [events]
        return builder.build()
    }
}
