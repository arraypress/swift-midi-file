//
//  Track.swift
//  MIDIFileKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One `MTrk` chunk: a named stream of notes.
public struct Track: Codable, Hashable, Sendable {

    /// Position in the file, from zero.
    public let index: Int

    /// The track name meta event, if it carried one.
    ///
    /// Worth more than it looks. Program change events are how General MIDI is supposed to say
    /// what plays a part, and the measured corpus contains **zero** of them across 1,200 files —
    /// but 99% carry a track name, and those names are the instrument: "Bass Layer 1", "Sub",
    /// "Massive 1", "303 Acid". If a caller wants to know what a part is, this is the field.
    public let name: String?

    /// The instrument name meta event (0x04), distinct from the track name and much rarer.
    public let instrument: String?

    /// Notes on this track.
    public let notes: [Note]

    /// Construct a track directly.
    public init(index: Int, name: String?, instrument: String?, notes: [Note]) {
        self.index = index
        self.name = name
        self.instrument = instrument
        self.notes = notes
    }

    /// Channels this track's notes used.
    public var channels: [Int] { Array(Set(notes.map(\.channel))).sorted() }

    /// The lowest and highest note, or nil if the track is silent.
    public var range: ClosedRange<Pitch>? {
        guard let low = notes.map(\.pitch).min(), let high = notes.map(\.pitch).max() else {
            return nil
        }
        return low ... high
    }

    /// Whether every note is on the percussion channel.
    public var isPercussion: Bool { !notes.isEmpty && notes.allSatisfy(\.isPercussion) }
}
