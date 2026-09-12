//
//  VariableLengthQuantity.swift
//  MIDIFileKit
//
//  Created by David Sherlock on 2026.
//
//  The seven-bits-at-a-time integer every MIDI delta time is written in.
//
//  High bit set means "another byte follows"; the value is the remaining seven bits of each
//  byte concatenated. The specification caps it at four bytes, and that cap is ENFORCED here
//  rather than trusted: a corrupt file with the high bit set in every byte would otherwise
//  spin through the whole track building a meaningless integer, and on a 64-bit accumulator
//  it would overflow and trap before it stopped.
//

import Foundation

enum VariableLengthQuantity {

    /// The most bytes the specification allows one quantity to occupy.
    static let maximumBytes = 4

    /// Read one quantity, returning its value and the offset just past it.
    ///
    /// - Throws: ``MIDIFileError/malformedVariableLengthQuantity(track:offset:)`` if the
    ///   quantity runs off the end of the buffer or past four bytes.
    static func read(from reader: inout ByteReader, track: Int) throws -> UInt32 {
        let start = reader.offset
        var value: UInt32 = 0
        for _ in 0 ..< maximumBytes {
            guard let next = reader.peek() else {
                throw MIDIFileError.malformedVariableLengthQuantity(track: track, offset: start)
            }
            _ = try reader.byte()
            value = (value << 7) | UInt32(next & 0x7F)
            if next & 0x80 == 0 { return value }
        }
        throw MIDIFileError.malformedVariableLengthQuantity(track: track, offset: start)
    }

    /// Encode a value as a variable-length quantity.
    ///
    /// Present so tests can build fixtures without a second, differently-buggy encoder —
    /// the round trip through ``read(from:track:)`` is the check that both agree.
    static func encode(_ value: UInt32) -> [UInt8] {
        var out = [UInt8(value & 0x7F)]
        var rest = value >> 7
        while rest > 0 {
            out.insert(UInt8((rest & 0x7F) | 0x80), at: 0)
            rest >>= 7
        }
        return out
    }
}
