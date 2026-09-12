//
//  Note.swift
//  MIDIFileKit
//
//  Created by David Sherlock on 2026.
//
//  One note: what was played, when, for how long, how hard.
//
//  This is the type that makes a MIDI file worth reading rather than listening to. An audio
//  analyser estimates pitch and onset and is sometimes wrong; here both are recorded facts.
//

import Foundation

/// A single sounding note, from its note-on to its matching note-off.
public struct Note: Codable, Hashable, Sendable {

    /// Which note.
    public let pitch: Pitch

    /// How hard it was struck, 1…127. Zero is not a velocity — it is a note-off in disguise.
    public let velocity: Int

    /// Velocity as a fraction, 0…1, for callers that would otherwise divide by 127 themselves.
    public var loudness: Double { Double(velocity) / 127 }

    /// MIDI channel, 0…15. Channel 9 is the percussion channel by convention.
    public let channel: Int

    /// Index of the track it came from.
    public let track: Int

    /// Start, in ticks from the beginning of the file.
    public let startTicks: Int

    /// Length, in ticks.
    public let durationTicks: Int

    /// Start, in quarter notes.
    public let startBeats: Double

    /// Length, in quarter notes.
    public let durationBeats: Double

    /// Start, in seconds, with every tempo change up to this point applied.
    public let startSeconds: Double

    /// Length, in seconds.
    public let durationSeconds: Double

    /// Construct a note directly.
    ///
    /// Public so callers can synthesise material to analyse — a scale to check a key
    /// estimate against, a progression built in code — without writing a MIDI file first.
    public init(pitch: Pitch, velocity: Int, channel: Int, track: Int,
                startTicks: Int, durationTicks: Int, startBeats: Double,
                durationBeats: Double, startSeconds: Double, durationSeconds: Double) {
        self.pitch = pitch
        self.velocity = velocity
        self.channel = channel
        self.track = track
        self.startTicks = startTicks
        self.durationTicks = durationTicks
        self.startBeats = startBeats
        self.durationBeats = durationBeats
        self.startSeconds = startSeconds
        self.durationSeconds = durationSeconds
    }

    /// The tick just past the end.
    public var endTicks: Int { startTicks + durationTicks }

    /// Whether this note is on the channel MIDI reserves for drums.
    ///
    /// A convention, not a guarantee — channel 10 (index 9) is percussion under General MIDI
    /// and most software honours it, but nothing in the format enforces it.
    public var isPercussion: Bool { channel == 9 }
}
