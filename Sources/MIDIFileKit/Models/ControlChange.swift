//
//  ControlChange.swift
//  MIDIFileKit
//
//  Created by David Sherlock on 2026.
//
//  A controller message: sustain pedal (64), modulation (1), volume (7) and
//  the rest. Carried at file level like a program change, on a channel,
//  because that is what the bytes say; the writer puts it on the track whose
//  notes use the channel.
//

import Foundation

/// A control change: `controller` set to `value` on `channel` at `atTicks`.
public struct ControlChange: Codable, Hashable, Sendable {

    /// Sustain pedal, controller 64: 64 and above is down.
    public static let sustainPedal = 64

    public let atTicks: Int
    public let channel: Int
    public let controller: Int
    public let value: Int

    public init(atTicks: Int, channel: Int, controller: Int, value: Int) {
        self.atTicks = atTicks
        self.channel = channel
        self.controller = min(127, max(0, controller))
        self.value = min(127, max(0, value))
    }
}
