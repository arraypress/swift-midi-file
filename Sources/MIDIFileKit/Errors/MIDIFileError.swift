//
//  MIDIFileError.swift
//  MIDIFileKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What can go wrong reading a Standard MIDI File.
public enum MIDIFileError: Error, Equatable, Sendable {

    /// The file is shorter than the header it claims to have.
    case truncated(at: Int)

    /// The first chunk was not `MThd`.
    ///
    /// Carries what was actually found, because the usual cause is a RIFF-wrapped `.rmi`
    /// or a renamed audio file and the four bytes say which.
    case notAMIDIFile(found: String)

    /// The header declared a format this reader does not handle.
    ///
    /// Formats 0, 1 and 2 are the whole of the specification; anything else is corruption.
    case unsupportedFormat(Int)

    /// A division of zero ticks per quarter note, which makes every timestamp meaningless.
    case invalidDivision

    /// A running-status byte appeared before any status byte established one.
    case runningStatusWithoutStatus(track: Int, offset: Int)

    /// A variable-length quantity ran past the end of its track.
    case malformedVariableLengthQuantity(track: Int, offset: Int)

    /// The file parsed, but contains no note at all.
    case noNotes
}

extension MIDIFileError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .truncated(let at):
            return "file ends mid-structure at byte \(at)"
        case .notAMIDIFile(let found):
            return "not a MIDI file — expected an MThd chunk, found '\(found)'"
        case .unsupportedFormat(let format):
            return "unsupported MIDI format \(format) — only 0, 1 and 2 exist"
        case .invalidDivision:
            return "header declares zero ticks per quarter note"
        case .runningStatusWithoutStatus(let track, let offset):
            return "track \(track): running status at byte \(offset) with no preceding status"
        case .malformedVariableLengthQuantity(let track, let offset):
            return "track \(track): variable-length quantity runs past the end at byte \(offset)"
        case .noNotes:
            return "file contains no notes"
        }
    }
}
