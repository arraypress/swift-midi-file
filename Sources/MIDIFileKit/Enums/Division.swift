//
//  Division.swift
//  MIDIFileKit
//
//  Created by David Sherlock on 2026.
//
//  What one tick means.
//

import Foundation

/// How a file's timestamps map onto time.
///
/// Two schemes exist and they are not interchangeable: musical time counts ticks per
/// quarter note and needs a tempo to become seconds, while SMPTE time counts frames and is
/// already absolute. Every file measured in this project's 6,013-file corpus was ``ticksPerQuarterNote``
/// — SMPTE division is a film-scoring feature that music software does not emit — but a
/// reader that assumed so would silently misreport any file that used it, so both are modelled.
public enum Division: Codable, Hashable, Sendable {

    /// Musical time: ticks per quarter note. Needs a tempo to become seconds.
    case ticksPerQuarterNote(Int)

    /// Absolute time: SMPTE frames per second, and ticks within each frame.
    ///
    /// - Parameters:
    ///   - framesPerSecond: 24, 25, 29 (drop-frame 30) or 30.
    ///   - ticksPerFrame: subdivisions of one frame.
    case smpte(framesPerSecond: Int, ticksPerFrame: Int)

    /// Parse the 16-bit division field of an `MThd` chunk.
    init(raw: UInt16) throws {
        if raw & 0x8000 != 0 {
            // Top bit set: the high byte is a negative frame rate, the low byte ticks/frame.
            let negated = Int(Int8(bitPattern: UInt8(raw >> 8)))
            let ticks = Int(raw & 0x00FF)
            guard ticks > 0, negated < 0 else { throw MIDIFileError.invalidDivision }
            self = .smpte(framesPerSecond: -negated, ticksPerFrame: ticks)
        } else {
            guard raw > 0 else { throw MIDIFileError.invalidDivision }
            self = .ticksPerQuarterNote(Int(raw))
        }
    }

    /// Ticks in one quarter note, or nil under SMPTE division where the question is meaningless.
    public var ticksPerQuarterNote: Int? {
        if case .ticksPerQuarterNote(let t) = self { return t }
        return nil
    }

    /// Ticks in one second, or nil under musical division where it depends on the tempo.
    public var ticksPerSecond: Double? {
        if case .smpte(let fps, let tpf) = self { return Double(fps) * Double(tpf) }
        return nil
    }
}
