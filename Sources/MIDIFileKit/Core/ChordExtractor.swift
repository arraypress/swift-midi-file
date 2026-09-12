//
//  ChordExtractor.swift
//  MIDIFileKit
//
//  Created by David Sherlock on 2026.
//
//  Which notes sound together, and what to call them.
//
//  The simultaneity is EXACT — a sweep over note-on and note-off boundaries, not a guess. What
//  is interpreted is only the name, and a name is withheld rather than invented when the notes
//  do not spell a chord anybody would recognise.
//

import Foundation

/// Finds simultaneous notes and names them.
public enum ChordExtractor {

    /// Chord qualities, as intervals above the root, ordered so that the first exact match
    /// wins. Longer and more specific patterns come first: [0,4,7,10] must be tried before
    /// [0,4,7] or every dominant seventh reports as a triad with a stray note.
    static let qualities: [(name: String, intervals: [Int])] = [
        ("maj9",  [0, 2, 4, 7, 11]),
        ("9",     [0, 2, 4, 7, 10]),
        ("m9",    [0, 2, 3, 7, 10]),
        ("maj7",  [0, 4, 7, 11]),
        ("7",     [0, 4, 7, 10]),
        ("m7",    [0, 3, 7, 10]),
        ("mMaj7", [0, 3, 7, 11]),
        ("m7b5",  [0, 3, 6, 10]),
        ("dim7",  [0, 3, 6, 9]),
        ("6",     [0, 4, 7, 9]),
        ("m6",    [0, 3, 7, 9]),
        ("add9",  [0, 2, 4, 7]),
        ("",      [0, 4, 7]),      // major triad, written bare: "C"
        ("m",     [0, 3, 7]),
        ("dim",   [0, 3, 6]),
        ("aug",   [0, 4, 8]),
        ("sus4",  [0, 5, 7]),
        ("sus2",  [0, 2, 7]),
        ("5",     [0, 7]),         // power chord: no third, so no mode — named honestly
    ]

    /// Every distinct simultaneity in a file, in order.
    ///
    /// - Parameters:
    ///   - notes: the notes to sweep.
    ///   - minimumVoices: how many notes must sound together to be reported. Two reports
    ///     intervals as well as chords; the default of three is what most callers mean by
    ///     "chord". 69% of the measured corpus never reaches three.
    ///   - minimumTicks: ignore simultaneities shorter than this. The reason this parameter
    ///     exists is that human or humanised playing does not strike a chord's notes at the
    ///     same instant, so a C major triad played with 8 ticks of spread produces, without
    ///     a floor, three spurious one- and two-note "chords" before the real one.
    ///   - includePercussion: channel 10's note numbers are drum identifiers, not pitches.
    ///   - tempoMap: used to place each chord in beats and seconds. Pass the map from the
    ///     file the notes came from; without it those two fields are reported as zero, because
    ///     a tick cannot be converted to a second without knowing the tempo and inventing one
    ///     would put every chord at the wrong time in a file that changes speed.
    public static func chords(in notes: [Note], minimumVoices: Int = 3,
                              minimumTicks: Int = 0,
                              includePercussion: Bool = false,
                              tempoMap: TempoMap? = nil) -> [Chord] {
        let pitched = includePercussion ? notes : notes.filter { !$0.isPercussion }
        guard !pitched.isEmpty else { return [] }

        // Every instant the sounding set can change is a note's start or end. Between two
        // consecutive boundaries the set is constant by construction, which is what makes
        // this exact rather than a sampling of the timeline.
        var boundaries = Set<Int>()
        for note in pitched where note.durationTicks > 0 {
            boundaries.insert(note.startTicks)
            boundaries.insert(note.endTicks)
        }
        let times = boundaries.sorted()
        guard times.count >= 2 else { return [] }

        var out: [Chord] = []
        for (index, start) in times.enumerated() where index + 1 < times.count {
            let end = times[index + 1]
            guard end - start >= minimumTicks else { continue }
            let sounding = pitched
                .filter { $0.startTicks <= start && $0.endTicks > start && $0.durationTicks > 0 }
                .map(\.pitch)
                .sorted()
            guard sounding.count >= minimumVoices else { continue }

            let named = name(sounding)
            let chord = Chord(startTicks: start, durationTicks: end - start,
                              startBeats: tempoMap?.beats(atTicks: start) ?? 0,
                              startSeconds: tempoMap?.seconds(atTicks: start) ?? 0,
                              pitches: sounding, name: named?.label,
                              root: named?.root, intervals: named?.intervals ?? [])
            // Merge with the previous span when the same notes are still sounding: a sweep
            // over boundaries splits a held chord at every passing note in another voice.
            if let last = out.last, last.pitches == chord.pitches,
               last.startTicks + last.durationTicks == chord.startTicks {
                out[out.count - 1] = Chord(startTicks: last.startTicks,
                                           durationTicks: last.durationTicks + chord.durationTicks,
                                           startBeats: last.startBeats,
                                           startSeconds: last.startSeconds,
                                           pitches: last.pitches, name: last.name,
                                           root: last.root, intervals: last.intervals)
            } else {
                out.append(chord)
            }
        }
        return out
    }

    /// Name a set of sounding pitches, or return nil if they spell nothing.
    ///
    /// Tries every pitch class present as a candidate root and requires an EXACT match against
    /// a quality's interval set. Exact, rather than nearest: a nearest-match namer will call
    /// any three notes something, and a name that is always produced carries no information.
    /// An inversion is written with a slash — C major over E is "C/E".
    static func name(_ pitches: [Pitch]) -> (label: String, root: Int, intervals: [Int])? {
        guard let bass = pitches.first else { return nil }
        var seen = Set<Int>()
        let classes = pitches.map(\.pitchClass).filter { seen.insert($0).inserted }
        guard classes.count >= 2 else { return nil }
        let classSet = Set(classes)

        for root in classes {
            let intervals = classSet.map { ($0 - root + 12) % 12 }.sorted()
            guard let quality = qualities.first(where: { $0.intervals == intervals }) else { continue }
            var label = Pitch.classNames[root] + quality.name
            if bass.pitchClass != root { label += "/" + bass.className }
            return (label, root, intervals)
        }
        return nil
    }

}

public extension MIDIFile {

    /// Every simultaneity in this file, with correct beat and second positions.
    ///
    /// The convenience that should be reached for by default — it passes this file's own
    /// tempo map, which the free function cannot know about.
    func chords(minimumVoices: Int = 3, minimumTicks: Int = 0,
                includePercussion: Bool = false) -> [Chord] {
        ChordExtractor.chords(in: notes, minimumVoices: minimumVoices,
                              minimumTicks: minimumTicks,
                              includePercussion: includePercussion, tempoMap: tempoMap)
    }

    /// The key these notes are in, as measured from the notes rather than as declared.
    ///
    /// See ``KeySignature`` for why ``declaredKeys`` should not be used for this.
    var estimatedKey: KeyEstimate? { KeyEstimator.estimate(notes: notes) }
}
