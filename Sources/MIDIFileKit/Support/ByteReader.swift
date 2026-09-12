//
//  ByteReader.swift
//  MIDIFileKit
//
//  Created by David Sherlock on 2026.
//
//  A cursor over bytes that refuses to read past the end.
//
//  Every multi-byte integer in a Standard MIDI File is BIG-endian, which is worth stating
//  once here because it is the opposite of almost everything else this fleet decodes —
//  Apple's protobuf colours are little-endian fixed32, and mixing the two up produces
//  plausible-looking nonsense rather than an error.
//

import Foundation

/// Reads big-endian integers and byte runs from a buffer, bounds-checked.
struct ByteReader {

    let bytes: [UInt8]
    private(set) var offset: Int

    init(_ bytes: [UInt8], at offset: Int = 0) {
        self.bytes = bytes
        self.offset = offset
    }

    var remaining: Int { bytes.count - offset }
    var isAtEnd: Bool { offset >= bytes.count }

    /// Whether `count` more bytes are available.
    func canRead(_ count: Int) -> Bool { remaining >= count }

    mutating func byte() throws -> UInt8 {
        guard offset < bytes.count else { throw MIDIFileError.truncated(at: offset) }
        defer { offset += 1 }
        return bytes[offset]
    }

    /// Peek at the next byte without consuming it.
    func peek() -> UInt8? { offset < bytes.count ? bytes[offset] : nil }

    mutating func uint16() throws -> UInt16 {
        guard canRead(2) else { throw MIDIFileError.truncated(at: offset) }
        defer { offset += 2 }
        return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    mutating func uint32() throws -> UInt32 {
        guard canRead(4) else { throw MIDIFileError.truncated(at: offset) }
        defer { offset += 4 }
        return UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
             | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
    }

    mutating func take(_ count: Int) throws -> [UInt8] {
        guard count >= 0, canRead(count) else { throw MIDIFileError.truncated(at: offset) }
        defer { offset += count }
        return Array(bytes[offset ..< offset + count])
    }

    /// Four bytes as ASCII — a chunk identifier.
    mutating func fourCC() throws -> String {
        let raw = try take(4)
        return String(decoding: raw, as: UTF8.self)
    }

    mutating func skip(_ count: Int) {
        offset = min(bytes.count, offset + count)
    }
}
