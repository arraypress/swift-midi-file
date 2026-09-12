//
//  Pitch.swift
//  MIDIFileKit
//
//  Created by David Sherlock on 2026.
//
//  A MIDI note number, and the names it goes by.
//

import Foundation

/// One of the 128 MIDI note numbers.
public struct Pitch: Codable, Hashable, Sendable, Comparable {

    /// Pitch class names, index 0 = C. Sharps, because MIDI carries no spelling.
    ///
    /// A MIDI file records note number 61 and nothing more; whether the composer meant
    /// C# or Db is information the format does not hold. Sharps are chosen and applied
    /// consistently rather than guessed at from context.
    public static let classNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// 0…127.
    public let number: Int

    public init(_ number: Int) {
        self.number = min(127, max(0, number))
    }

    /// 0 = C, 11 = B.
    public var pitchClass: Int { number % 12 }

    /// Scientific pitch notation octave: middle C (60) is C4.
    ///
    /// The alternative convention puts middle C at C3, and both are in wide use. C4 is
    /// chosen because it is what the MIDI Manufacturers Association specifies.
    public var octave: Int { number / 12 - 1 }

    /// The class name without the octave — "C#".
    public var className: String { Self.classNames[pitchClass] }

    /// The full name — "C#4".
    public var name: String { "\(className)\(octave)" }

    /// Equal-tempered frequency with A4 at 440 Hz.
    public var frequency: Double { 440 * pow(2, Double(number - 69) / 12) }

    public static func < (lhs: Pitch, rhs: Pitch) -> Bool { lhs.number < rhs.number }
}
