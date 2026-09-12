//
//  TimeSignature.swift
//  MIDIFileKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// A time signature, in force from one tick until the next change.
public struct TimeSignature: Codable, Hashable, Sendable {

    /// Where it takes effect.
    public let atTicks: Int

    /// Beats per bar — the top number.
    public let numerator: Int

    /// Which note value gets the beat — the bottom number, always a power of two.
    public let denominator: Int

    /// MIDI clocks per metronome click. Carried because the file carries it; rarely useful.
    public let clocksPerClick: Int

    /// Thirty-second notes per quarter note — 8 unless somebody is being clever.
    public let thirtySecondsPerQuarter: Int

    /// Construct a time signature directly.
    public init(atTicks: Int, numerator: Int, denominator: Int,
                clocksPerClick: Int = 24, thirtySecondsPerQuarter: Int = 8) {
        self.atTicks = atTicks
        self.numerator = numerator
        self.denominator = denominator
        self.clocksPerClick = clocksPerClick
        self.thirtySecondsPerQuarter = thirtySecondsPerQuarter
    }

    /// "4/4".
    public var label: String { "\(numerator)/\(denominator)" }

    /// How many quarter notes are in one bar.
    public var beatsPerBar: Double {
        guard denominator > 0 else { return 0 }
        return Double(numerator) * 4 / Double(denominator)
    }

    /// The signature assumed before a file says otherwise: 4/4, per the specification.
    public static let `default` = TimeSignature(atTicks: 0, numerator: 4, denominator: 4,
                                                clocksPerClick: 24, thirtySecondsPerQuarter: 8)
}
