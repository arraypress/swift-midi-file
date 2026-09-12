//
//  Chord.swift
//  MIDIFileKit
//
//  Created by David Sherlock on 2026.
//
//  What is sounding at one moment.
//
//  THIS IS WHERE MIDI BEATS AUDIO OUTRIGHT, and it is worth being precise about why. A chord
//  read from audio is an estimate over a smeared spectrum — this fleet's own ``AudioTimbre``
//  abandoned its chord namer after it called nine of twenty kick drums "F", because a
//  fundamental and its harmonic series look exactly like a major triad. Here the notes are
//  recorded facts: which pitches overlap in time is not inferred, it is read. Only the NAME
//  is an interpretation, and the members are reported either way so a caller who distrusts
//  the naming still has the data.
//

import Foundation

/// A set of notes sounding together, and what they add up to.
public struct Chord: Codable, Hashable, Sendable {

    /// When it starts, in ticks.
    public let startTicks: Int

    /// How long this exact set of notes holds, in ticks.
    public let durationTicks: Int

    /// Start in quarter notes from the beginning.
    public let startBeats: Double

    /// Start in seconds.
    public let startSeconds: Double

    /// Every pitch sounding, lowest first. A recorded fact, not an estimate.
    public let pitches: [Pitch]

    /// Construct a chord directly.
    public init(startTicks: Int, durationTicks: Int, startBeats: Double, startSeconds: Double,
                pitches: [Pitch], name: String?, root: Int?, intervals: [Int]) {
        self.startTicks = startTicks
        self.durationTicks = durationTicks
        self.startBeats = startBeats
        self.startSeconds = startSeconds
        self.pitches = pitches
        self.name = name
        self.root = root
        self.intervals = intervals
    }

    /// The lowest sounding pitch — the bass note, which decides an inversion.
    public var bass: Pitch? { pitches.first }

    /// Distinct pitch classes present, lowest-sounding first.
    public var pitchClasses: [Int] {
        var seen = Set<Int>()
        return pitches.map(\.pitchClass).filter { seen.insert($0).inserted }
    }

    /// How many notes sound at once.
    public var voices: Int { pitches.count }

    /// The chord's name — "F#m", "Cmaj7", "G/B" — or nil if the notes name nothing.
    ///
    /// Nil is a real and frequent answer: two notes are an interval and not a chord, and a
    /// cluster of seconds has no name worth inventing. 69% of the measured corpus never has
    /// three notes sounding at once, so most files produce no named chords at all.
    public let name: String?

    /// The interpreted root, when a name was found.
    public let root: Int?

    /// The interval pattern above the root, in semitones — the evidence behind ``name``.
    public let intervals: [Int]
}
