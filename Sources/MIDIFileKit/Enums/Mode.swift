//
//  Mode.swift
//  MIDIFileKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Major or minor.
///
/// Deliberately has no `unknown` case. A mode that could not be determined is represented by
/// `nil` wherever one is optional — see ``KeyEstimate/mode`` — so that the type system forces
/// a caller to handle "we could not tell" instead of letting it hide inside the enum and be
/// rendered as a third kind of key.
public enum Mode: String, Codable, Hashable, Sendable, CaseIterable {
    case major
    case minor

    /// The single-letter suffix convention: "Am" is A minor, "A" is A major.
    public var suffix: String { self == .minor ? "m" : "" }
}
