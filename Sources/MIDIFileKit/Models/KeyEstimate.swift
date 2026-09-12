//
//  KeyEstimate.swift
//  MIDIFileKit
//
//  Created by David Sherlock on 2026.
//
//  The key as the NOTES have it, not as the file claims — and an honest account of how much
//  of that is knowable from this file.
//
//  MEASURED ACCURACY, against 6,013 commercial trance and techno MIDI files whose folders or
//  filenames name a key. All figures are from the shipping code over the whole corpus, not a
//  sample of it:
//
//    root, one file                                   77%   (2,403 files)
//    root, one folder pooled — any size                67%   (124 folders)
//    root, one folder pooled — 10+ files               89%   (69 folders)
//    root, one folder pooled — 20+ files               92%   (66 folders)
//    root + mode, one file                             37%   (108 files labelled with a mode)
//    root + mode, where the file contains a third      64%   (62 of those 108)
//
//  Two things to read off that table. Pooling a folder helps a great deal and keeps helping up
//  to about twenty files — see ``KeyEstimator/estimate(pooling:)``. And the remaining pooled
//  failures are mostly not failures: they are folders like "Chord Loops" that hold material in
//  several keys, where averaging produces a key nothing in the folder is in. One had a
//  correlation of 0.37, which ``isWellSupported`` already rejects.
//
//  The gap between 77% and 37% is not a tuning failure and no profile set closes it. It is that
//  **42% of the mode-labelled files contain no third at all** — they are basslines and sub
//  parts, 19 of 108 used a single pitch class — and the interval that separates major from minor
//  is simply not in the data. Restricting to files that do contain a third lifts 37% to 64%.
//
//  So ``mode`` is OPTIONAL and is nil when the evidence is absent. That is the whole design.
//  A library that always returned a mode would be wrong most of the time on this corpus while
//  looking exactly as confident as when it is right.
//
//  The profile set is Krumhansl-Kessler, chosen by measurement over Temperley, Albrecht-Shanahan,
//  Aarden and a flat binary mask — 66% against 44%, 59%, 42% and 25% respectively on the same
//  ground truth. Weighting by note duration beat weighting by note count on mode and tied on
//  root, so duration is used.
//

import Foundation

/// A key inferred from the notes, with the evidence for it.
public struct KeyEstimate: Codable, Hashable, Sendable {

    /// The tonic pitch class, 0 = C.
    public let root: Int

    /// The tonic's name — "F#".
    public var rootName: String { Pitch.classNames[root] }

    /// Major or minor — **nil when the notes do not say**.
    ///
    /// Nil means the file contains neither a major nor a minor third above the root, which is
    /// the case for 43% of single-part files in the measured corpus. It is not a low-confidence
    /// guess withheld; it is the absence of the only interval that carries the answer.
    public let mode: Mode?

    /// Correlation of the pitch class profile against the winning template, −1…1.
    ///
    /// Around 0.7 for a clear loop and 0.9 for a full pooled folder. Below about 0.5 the
    /// material is either atonal or percussive and the root means little.
    public let correlation: Double

    /// How far the winner beat the runner-up with a different root.
    ///
    /// The honest confidence signal. A high correlation means the notes fit the template; a
    /// high margin means they fit THIS template and not the next one, which is the question a
    /// caller actually has.
    public let margin: Double

    /// How many distinct pitch classes the material used, 0…12.
    ///
    /// One or two means no key can be meant seriously — a single-note sub bass correlates
    /// respectably against twelve different templates.
    public let distinctPitchClasses: Int

    /// Whether a third above the root was present, which is what made ``mode`` determinable.
    public let hasThird: Bool

    /// The twelve pitch classes' total sounding duration in quarter notes, C first.
    public let weights: [Double]

    /// Construct an estimate directly.
    ///
    /// Rarely wanted — ``KeyEstimator`` produces these — but public so a caller can render
    /// a stored estimate without keeping the notes that produced it.
    public init(root: Int, mode: Mode?, correlation: Double, margin: Double,
                distinctPitchClasses: Int, hasThird: Bool, weights: [Double]) {
        self.root = root
        self.mode = mode
        self.correlation = correlation
        self.margin = margin
        self.distinctPitchClasses = distinctPitchClasses
        self.hasThird = hasThird
        self.weights = weights
    }

    /// "F#m", or "F#" with the mode undetermined — never a guessed mode.
    public var name: String {
        guard let mode else { return rootName }
        return rootName + mode.suffix
    }

    /// A line that states the uncertainty rather than hiding it.
    public var summary: String {
        var text = name
        if mode == nil { text += " (mode undetermined — no third in this part)" }
        text += String(format: " · r=%.2f margin %.2f · %d pitch classes",
                       correlation, margin, distinctPitchClasses)
        return text
    }

    /// Whether this estimate rests on enough distinct notes to be worth showing.
    ///
    /// Three pitch classes is the floor: two can be a root and a fifth, which is every key
    /// that contains both and is most of them.
    ///
    /// **This is a guard for ``mode``, and using it to filter ROOTS makes them worse.**
    /// Measured over 2,254 ground-truth loops: naming every file gives 80% root accuracy,
    /// while keeping only the well-supported ones gives **69%**. The gate removes files with
    /// one or two pitch classes — and a one-note bassline is the EASIEST root to get right,
    /// so filtering on this throws away the sure things and keeps the arguable ones.
    ///
    /// To filter roots, use ``margin`` instead, which behaves the way a confidence should:
    /// 81% at 0.10, 87% at 0.15, 90% at 0.20, for 43%, 35% and 29% of files respectively.
    /// Better still, pool the folder — see ``KeyEstimator/estimate(pooling:)``.
    public var isWellSupported: Bool { distinctPitchClasses >= 3 && correlation >= 0.5 }
}
