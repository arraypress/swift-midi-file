//
//  PitchBend.swift
//  MIDIFileKit
//
//  Created by David Sherlock on 2026.
//
//  A pitch-bend message: a 14-bit value, 8192 at centre, on a channel. Carried
//  at file level like a control change; the writer puts it on the track whose
//  notes use the channel. `semitones` reads it against a bend range, which the
//  file does not record — ±2 semitones is General MIDI's default.
//

import Foundation

/// A pitch bend of `value` (0…16383, centre 8192) on `channel` at `atTicks`.
public struct PitchBend: Codable, Hashable, Sendable {

    public static let centre = 8192
    public static let maximum = 16383

    public let atTicks: Int
    public let channel: Int
    public let value: Int

    public init(atTicks: Int, channel: Int, value: Int) {
        self.atTicks = atTicks
        self.channel = channel
        self.value = min(Self.maximum, max(0, value))
    }

    /// The bend as a fraction of the range, −1…1.
    public var fraction: Double { Double(value - Self.centre) / Double(value >= Self.centre ? Self.maximum - Self.centre : Self.centre) }

    /// The bend in semitones for a bend range of `range` semitones each way (General MIDI's default is 2).
    public func semitones(range: Double = 2) -> Double { fraction * range }

    /// The 14-bit value for a bend of `semitones` within a range of `range` each way, clamped.
    public static func value(semitones: Double, range: Double = 2) -> Int {
        let fraction = max(-1, min(1, semitones / range))
        return fraction >= 0 ? centre + Int((fraction * Double(maximum - centre)).rounded()) : centre + Int((fraction * Double(centre)).rounded())
    }
}
