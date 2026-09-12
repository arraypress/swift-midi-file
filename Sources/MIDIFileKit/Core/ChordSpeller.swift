//
//  ChordSpeller.swift
//  MIDIFileKit
//
//  Created by David Sherlock on 2026.
//
//  A chord name in, notes out — the reverse of ``ChordExtractor/name(_:)``.
//
//  The two share one table, ``ChordExtractor/qualities``, so a name this produces is a name
//  that reads back. That is asserted rather than assumed: ``ChordSpellerTests`` spells every
//  quality in all twelve roots, extracts the result, and requires the name to survive the
//  round trip. If a quality is ever added to the table, both directions get it at once.
//

import Foundation

/// Turns a chord name into pitches.
public enum ChordSpeller {

    /// Spell a chord name — "F#m9", "Cmaj7", "Bb5", "C/E" — as sounding pitches.
    ///
    /// - Parameters:
    ///   - name: root, then quality, optionally `/bass` for an inversion. Flats are accepted
    ///     even though this library spells with sharps, because a person writing a recipe
    ///     thinks in whichever the key uses.
    ///   - octave: which octave the root sits in, scientific pitch notation, so 3 puts the
    ///     root of a C chord at C3. Extensions stack upward from there.
    /// - Returns: pitches low to high, or nil if the name names nothing.
    public static func pitches(for name: String, octave: Int = 3) -> [Pitch]? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Split an inversion off first: "C/E" is a C chord voiced over E.
        let halves = trimmed.split(separator: "/", maxSplits: 1).map(String.init)
        guard let chordPart = halves.first else { return nil }
        let bassName = halves.count > 1 ? halves[1] : nil

        guard let (root, quality) = split(chordPart) else { return nil }
        guard let intervals = ChordExtractor.qualities.first(where: {
            $0.name.lowercased() == quality.lowercased()
        })?.intervals else { return nil }

        let base = (octave + 1) * 12 + root
        var numbers = intervals.map { base + $0 }

        if let bassName, let bassClass = pitchClass(of: bassName) {
            // Put the named bass below everything, dropping the duplicate from the stack so
            // the chord keeps its voice count.
            let bass = base - 12 + ((bassClass - root + 12) % 12)
            numbers.removeAll { $0 % 12 == bassClass % 12 }
            numbers.insert(bass < 0 ? bass + 12 : bass, at: 0)
        }

        let pitches = numbers.filter { (0...127).contains($0) }.sorted().map(Pitch.init)
        return pitches.isEmpty ? nil : pitches
    }

    /// Every quality this understands, longest-named first — "maj9" before "maj7" before "".
    public static var qualityNames: [String] {
        ChordExtractor.qualities.map(\.name)
    }

    // MARK: - Private

    /// Split "F#m9" into pitch class 6 and quality "m9".
    private static func split(_ text: String) -> (root: Int, quality: String)? {
        var index = text.startIndex
        guard let letter = text.first,
              let base = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11][String(letter).uppercased()]
        else { return nil }
        index = text.index(after: index)

        var accidental = 0
        while index < text.endIndex, text[index] == "#" || text[index] == "b" {
            accidental += text[index] == "#" ? 1 : -1
            index = text.index(after: index)
        }
        let root = ((base + accidental) % 12 + 12) % 12
        return (root, String(text[index...]))
    }

    private static func pitchClass(of name: String) -> Int? {
        split(name).map(\.root)
    }
}
