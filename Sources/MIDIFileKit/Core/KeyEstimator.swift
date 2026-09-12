//
//  KeyEstimator.swift
//  MIDIFileKit
//
//  Created by David Sherlock on 2026.
//
//  What key is this in, and how much of that does the file actually know?
//
//  The method is template correlation over a duration-weighted pitch class profile —
//  Krumhansl-Kessler, picked by measuring five published profile sets against the same
//  ground truth. See ``KeyEstimate`` for the accuracy table and for why ``KeyEstimate/mode``
//  is optional rather than always answered.
//

import Foundation

/// Infers a key from notes.
public enum KeyEstimator {

    /// Krumhansl-Kessler major profile: how strongly each scale degree belongs to a major key.
    ///
    /// From the probe-tone experiments, not from theory — the reason the tonic (6.35) only
    /// narrowly beats the fifth (5.19) is that listeners really do rate them that closely.
    static let majorProfile = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]

    /// Krumhansl-Kessler minor profile.
    static let minorProfile = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    /// Estimate the key of a set of notes.
    ///
    /// - Parameters:
    ///   - notes: any notes; percussion is excluded automatically, since a drum part's note
    ///     numbers are instrument identifiers and not pitches, and including them moves the
    ///     answer toward whatever the kit's numbering happens to spell.
    ///   - includePercussion: pass true to weigh channel 10 like any other.
    /// - Returns: nil if nothing pitched was played.
    public static func estimate(notes: [Note], includePercussion: Bool = false) -> KeyEstimate? {
        let pitched = includePercussion ? notes : notes.filter { !$0.isPercussion }
        guard !pitched.isEmpty else { return nil }

        var weights = [Double](repeating: 0, count: 12)
        for note in pitched {
            // Duration-weighted: measured 66% against 68% for count-weighting on root, but
            // count-weighting lost 6 points on mode, and mode is the harder question.
            // A zero-length note still counts as struck, hence the floor.
            weights[note.pitch.pitchClass] += max(note.durationBeats, 0.03125)
        }
        let total = weights.reduce(0, +)
        guard total > 0 else { return nil }

        var scored: [(correlation: Double, root: Int, mode: Mode)] = []
        for root in 0 ..< 12 {
            let rotated = (0 ..< 12).map { weights[($0 + root) % 12] }
            scored.append((correlate(rotated, majorProfile), root, .major))
            scored.append((correlate(rotated, minorProfile), root, .minor))
        }
        scored.sort { $0.correlation > $1.correlation }
        guard let best = scored.first else { return nil }

        let present = Set(pitched.map(\.pitch.pitchClass))
        let hasMinorThird = present.contains((best.root + 3) % 12)
        let hasMajorThird = present.contains((best.root + 4) % 12)
        let hasThird = hasMinorThird || hasMajorThird

        // The whole point of the type. With no third in the material the major and minor
        // templates are being separated by the sixth and seventh degrees alone, which on a
        // four-note bassline is noise — measured as a coin flip, 80 major to 80 minor across
        // one folder of 160 files that were all in the same minor key.
        let mode: Mode?
        if hasThird {
            mode = (hasMinorThird && !hasMajorThird) ? .minor
                 : (hasMajorThird && !hasMinorThird) ? .major
                 : best.mode      // both present — let the profile correlation decide
        } else {
            mode = nil
        }

        let runnerUp = scored.first { $0.root != best.root }?.correlation ?? 0

        return KeyEstimate(root: best.root, mode: mode, correlation: best.correlation,
                           margin: best.correlation - runnerUp,
                           distinctPitchClasses: present.count, hasThird: hasThird,
                           weights: weights)
    }

    /// Estimate one key from several files' notes pooled together.
    ///
    /// The reason this exists: a sample pack's loops are individually too thin to place a mode
    /// on — 42% contain no third — but a folder of fifty of them is not. Measured over the
    /// corpus, pooling lifts root accuracy from 77% per file to 89% for folders of ten or more
    /// and 92% for folders of twenty or more, and it recovers the minor mode in 93% of folders
    /// where per-file mode estimation was a coin flip.
    ///
    /// Only pool material that belongs together, and check ``KeyEstimate/isWellSupported`` on
    /// the result. Two packs in different keys average to a third key that neither is in —
    /// every pooled failure measured was a folder like "Chord Loops" holding several keys, and
    /// the low correlation is what gives them away.
    public static func estimate(pooling groups: [[Note]]) -> KeyEstimate? {
        estimate(notes: groups.flatMap { $0 })
    }

    /// Pearson correlation. Returns 0 when either side is flat, which is the honest answer
    /// for a single repeated pitch class rather than a division by zero.
    static func correlate(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let n = Double(a.count)
        let meanA = a.reduce(0, +) / n
        let meanB = b.reduce(0, +) / n
        var numerator = 0.0, sumA = 0.0, sumB = 0.0
        for i in a.indices {
            let da = a[i] - meanA, db = b[i] - meanB
            numerator += da * db
            sumA += da * da
            sumB += db * db
        }
        let denominator = (sumA * sumB).squareRoot()
        return denominator > 0 ? numerator / denominator : 0
    }
}
