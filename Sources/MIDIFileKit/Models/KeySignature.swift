//
//  KeySignature.swift
//  MIDIFileKit
//
//  Created by David Sherlock on 2026.
//
//  The key the FILE CLAIMS to be in — which is very often not the key it is in.
//
//  THIS IS THE LEAST TRUSTWORTHY FIELD IN THE FORMAT, and the measurement that says so is
//  worth recording: across a 6,013-file corpus of commercial trance and techno MIDI, every
//  single key signature event — 895 of 895 — declared C major. Not one of those files was in
//  C major. The event is written once by the DAW at its default and never updated, so it
//  records the software's initial state rather than anything about the music.
//
//  It is surfaced anyway, because a reader is entitled to see what the bytes say. But
//  ``KeyEstimate``, computed from the notes, is the field a caller should believe, and the
//  two are deliberately different types so no one can substitute one for the other by accident.
//

import Foundation

/// The key signature meta event, as written in the file.
public struct KeySignature: Codable, Hashable, Sendable {

    /// Where it takes effect.
    public let atTicks: Int

    /// Sharps if positive, flats if negative, −7…7.
    public let accidentals: Int

    /// Major or minor, as declared.
    public let mode: Mode

    /// Construct a key signature directly.
    public init(atTicks: Int, accidentals: Int, mode: Mode) {
        self.atTicks = atTicks
        self.accidentals = accidentals
        self.mode = mode
    }

    /// The tonic implied by the accidental count and mode — "C", "F#m".
    ///
    /// Uses the conventional spelling for each signature, so −3 major is "Eb" rather than
    /// "D#". This is the one place in the library flats appear: a key signature genuinely
    /// carries a spelling where a note number does not.
    public var name: String {
        let major = ["Cb", "Gb", "Db", "Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#"]
        let minor = ["Abm", "Ebm", "Bbm", "Fm", "Cm", "Gm", "Dm", "Am", "Em", "Bm", "F#m",
                     "C#m", "G#m", "D#m", "A#m"]
        let index = accidentals + 7
        guard index >= 0, index < major.count else { return "?" }
        return mode == .major ? major[index] : minor[index]
    }

    /// Whether this is the value a DAW writes when nobody has set one: C major, no accidentals.
    ///
    /// Not proof the field is wrong — some music really is in C major — but in a corpus where
    /// it is true of 100% of files it is the signal that the field carries no information.
    /// A caller showing a key to a user should check this before showing this one.
    public var isProbablyADefault: Bool { accidentals == 0 && mode == .major }
}
