//
//  Tempo.swift
//  MIDIFileKit
//
//  Created by David Sherlock on 2026.
//
//  Tempo, and the map that turns ticks into seconds.
//

import Foundation

/// A tempo, in force from one tick until the next change.
public struct Tempo: Codable, Hashable, Sendable {

    /// Where this tempo takes effect.
    public let atTicks: Int

    /// Microseconds per quarter note — how the file actually stores it.
    public let microsecondsPerQuarterNote: Int

    /// Quarter notes per minute.
    public var bpm: Double {
        guard microsecondsPerQuarterNote > 0 else { return 0 }
        return 60_000_000 / Double(microsecondsPerQuarterNote)
    }

    public init(atTicks: Int, microsecondsPerQuarterNote: Int) {
        self.atTicks = atTicks
        self.microsecondsPerQuarterNote = microsecondsPerQuarterNote
    }

    /// The tempo a file is assumed to be at before it says otherwise: 120 bpm.
    ///
    /// Specified, not invented — a file with no tempo event is 120 bpm by definition, and
    /// 6 files in every 800 of the measured corpus rely on it.
    public static let `default` = Tempo(atTicks: 0, microsecondsPerQuarterNote: 500_000)
}

/// Every tempo in a file, in order, with the arithmetic to convert a tick to a second.
public struct TempoMap: Codable, Hashable, Sendable {

    /// Tempo changes in tick order. Never empty: a file with none gets ``Tempo/default``.
    public let tempos: [Tempo]

    /// Ticks per quarter note, or nil under SMPTE division.
    public let ticksPerQuarterNote: Int?

    /// Seconds per tick under SMPTE division, where tempo does not apply.
    private let smpteSecondsPerTick: Double?

    init(tempos: [Tempo], division: Division) {
        self.tempos = tempos.isEmpty ? [.default] : tempos.sorted { $0.atTicks < $1.atTicks }
        self.ticksPerQuarterNote = division.ticksPerQuarterNote
        self.smpteSecondsPerTick = division.ticksPerSecond.map { 1 / $0 }
    }

    /// Whether the tempo ever changes.
    public var isConstant: Bool { tempos.count == 1 }

    /// The tempo at the start.
    public var initial: Tempo { tempos[0] }

    /// The one tempo this file is in, or nil if it changes.
    ///
    /// Separate from ``initial`` on purpose. A caller labelling a loop wants to know the
    /// tempo and wants nothing at all if the answer is "it depends"; reporting the first of
    /// several as though it were the tempo is how a 90-to-180 ramp gets filed under 90.
    public var single: Tempo? { isConstant ? tempos[0] : nil }

    /// Convert a tick position to seconds, applying every tempo change before it.
    ///
    /// Walks the map rather than scaling by the initial tempo, so an accelerating file
    /// converts correctly. The cost is linear in the number of tempo changes, which in the
    /// measured corpus is one.
    public func seconds(atTicks tick: Int) -> Double {
        if let perTick = smpteSecondsPerTick { return Double(tick) * perTick }
        guard let tpqn = ticksPerQuarterNote, tpqn > 0 else { return 0 }

        var seconds = 0.0
        var cursor = 0
        var current = tempos[0]

        for change in tempos where change.atTicks < tick {
            if change.atTicks > cursor {
                seconds += Double(change.atTicks - cursor)
                    * Double(current.microsecondsPerQuarterNote) / Double(tpqn) / 1_000_000
                cursor = change.atTicks
            }
            current = change
        }
        seconds += Double(tick - cursor)
            * Double(current.microsecondsPerQuarterNote) / Double(tpqn) / 1_000_000
        return seconds
    }

    /// Convert a tick position to quarter notes.
    public func beats(atTicks tick: Int) -> Double {
        guard let tpqn = ticksPerQuarterNote, tpqn > 0 else { return 0 }
        return Double(tick) / Double(tpqn)
    }
}
