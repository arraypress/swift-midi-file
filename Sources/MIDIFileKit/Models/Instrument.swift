//
//  Instrument.swift
//  MIDIFileKit
//
//  Created by David Sherlock on 2026.
//
//  Which instrument plays a part.
//
//  Two entirely separate mechanisms answer this, and a file usually has only one of them:
//
//  PROGRAM CHANGE is the formal one — a General MIDI program number, 0…127, with a standard
//  name. Full arrangements and anything exported for a hardware module carry these.
//
//  TRACK NAME is the informal one, and in loop libraries it is the only one. Across 1,200
//  files of the measured corpus there were **zero** program changes and 99% carried a track
//  name — "Bass Layer 1", "Sub", "Massive 1", "303 Acid". A reader that only understood
//  program changes would report that corpus as having no instruments at all.
//
//  Both are surfaced, neither is invented, and ``Channel/label`` prefers whichever exists.
//

import Foundation

/// A General MIDI program selection on one channel.
public struct Instrument: Codable, Hashable, Sendable {

    /// Where the change takes effect.
    public let atTicks: Int

    /// MIDI channel, 0…15.
    public let channel: Int

    /// General MIDI program number, 0…127.
    public let program: Int

    /// Construct a program selection directly.
    public init(atTicks: Int, channel: Int, program: Int) {
        self.atTicks = atTicks
        self.channel = channel
        self.program = program
    }

    /// Whether this is on the channel MIDI reserves for percussion.
    ///
    /// On channel 10 the program number selects a DRUM KIT, not an instrument, and the note
    /// numbers are individual drums rather than pitches — so ``name`` would be meaningless
    /// and is replaced by the kit name.
    public var isDrumKit: Bool { channel == 9 }

    /// The General MIDI name — "Acoustic Grand Piano", "Fretless Bass", "Standard Kit".
    public var name: String {
        if isDrumKit { return Self.drumKitName(program) }
        guard program >= 0, program < Self.generalMIDINames.count else { return "Program \(program)" }
        return Self.generalMIDINames[program]
    }

    /// The General MIDI family — "Piano", "Bass", "Synth Lead", "Drum Kit".
    public var family: String {
        if isDrumKit { return "Drum Kit" }
        guard program >= 0, program < 128 else { return "Unknown" }
        return Self.families[program / 8]
    }

    /// The sixteen General MIDI families, in program order.
    public static let families = [
        "Piano", "Chromatic Percussion", "Organ", "Guitar", "Bass", "Strings", "Ensemble",
        "Brass", "Reed", "Pipe", "Synth Lead", "Synth Pad", "Synth Effects", "Ethnic",
        "Percussive", "Sound Effects"
    ]

    /// Drum kits are selected by program number on channel 10, at these fixed points.
    /// A program that is not a kit boundary falls back to the kit below it.
    static func drumKitName(_ program: Int) -> String {
        let kits: [(Int, String)] = [
            (0, "Standard Kit"), (8, "Room Kit"), (16, "Power Kit"), (24, "Electronic Kit"),
            (25, "TR-808 Kit"), (32, "Jazz Kit"), (40, "Brush Kit"), (48, "Orchestra Kit"),
            (56, "Sound FX Kit")
        ]
        return kits.last { program >= $0.0 }?.1 ?? "Standard Kit"
    }

    /// The 128 General MIDI Level 1 program names, in order.
    public static let generalMIDINames = [
        "Acoustic Grand Piano", "Bright Acoustic Piano", "Electric Grand Piano",
        "Honky-tonk Piano", "Electric Piano 1", "Electric Piano 2", "Harpsichord", "Clavi",
        "Celesta", "Glockenspiel", "Music Box", "Vibraphone", "Marimba", "Xylophone",
        "Tubular Bells", "Dulcimer",
        "Drawbar Organ", "Percussive Organ", "Rock Organ", "Church Organ", "Reed Organ",
        "Accordion", "Harmonica", "Tango Accordion",
        "Acoustic Guitar (nylon)", "Acoustic Guitar (steel)", "Electric Guitar (jazz)",
        "Electric Guitar (clean)", "Electric Guitar (muted)", "Overdriven Guitar",
        "Distortion Guitar", "Guitar Harmonics",
        "Acoustic Bass", "Electric Bass (finger)", "Electric Bass (pick)", "Fretless Bass",
        "Slap Bass 1", "Slap Bass 2", "Synth Bass 1", "Synth Bass 2",
        "Violin", "Viola", "Cello", "Contrabass", "Tremolo Strings", "Pizzicato Strings",
        "Orchestral Harp", "Timpani",
        "String Ensemble 1", "String Ensemble 2", "SynthStrings 1", "SynthStrings 2",
        "Choir Aahs", "Voice Oohs", "Synth Voice", "Orchestra Hit",
        "Trumpet", "Trombone", "Tuba", "Muted Trumpet", "French Horn", "Brass Section",
        "SynthBrass 1", "SynthBrass 2",
        "Soprano Sax", "Alto Sax", "Tenor Sax", "Baritone Sax", "Oboe", "English Horn",
        "Bassoon", "Clarinet",
        "Piccolo", "Flute", "Recorder", "Pan Flute", "Blown Bottle", "Shakuhachi",
        "Whistle", "Ocarina",
        "Lead 1 (square)", "Lead 2 (sawtooth)", "Lead 3 (calliope)", "Lead 4 (chiff)",
        "Lead 5 (charang)", "Lead 6 (voice)", "Lead 7 (fifths)", "Lead 8 (bass + lead)",
        "Pad 1 (new age)", "Pad 2 (warm)", "Pad 3 (polysynth)", "Pad 4 (choir)",
        "Pad 5 (bowed)", "Pad 6 (metallic)", "Pad 7 (halo)", "Pad 8 (sweep)",
        "FX 1 (rain)", "FX 2 (soundtrack)", "FX 3 (crystal)", "FX 4 (atmosphere)",
        "FX 5 (brightness)", "FX 6 (goblins)", "FX 7 (echoes)", "FX 8 (sci-fi)",
        "Sitar", "Banjo", "Shamisen", "Koto", "Kalimba", "Bag pipe", "Fiddle", "Shanai",
        "Tinkle Bell", "Agogo", "Steel Drums", "Woodblock", "Taiko Drum", "Melodic Tom",
        "Synth Drum", "Reverse Cymbal",
        "Guitar Fret Noise", "Breath Noise", "Seashore", "Bird Tweet", "Telephone Ring",
        "Helicopter", "Applause", "Gunshot"
    ]
}

/// Everything one MIDI channel contains — the view a caller wants for a full arrangement.
public struct Channel: Codable, Hashable, Sendable {

    /// 0…15.
    public let number: Int

    /// Programs selected on this channel, in order. Usually one; a channel that switches
    /// instrument mid-piece has several, and reporting only the first would misname the rest.
    public let instruments: [Instrument]

    /// Track names of the tracks whose notes landed on this channel.
    public let trackNames: [String]

    /// How many notes played here.
    public let noteCount: Int

    /// Lowest and highest note, or nil if silent.
    public let range: ClosedRange<Pitch>?

    /// Construct a channel summary directly.
    public init(number: Int, instruments: [Instrument], trackNames: [String],
                noteCount: Int, range: ClosedRange<Pitch>?) {
        self.number = number
        self.instruments = instruments
        self.trackNames = trackNames
        self.noteCount = noteCount
        self.range = range
    }

    /// Whether this is the percussion channel.
    public var isPercussion: Bool { number == 9 }

    /// The best available name for what plays here.
    ///
    /// Prefers the General MIDI program, falls back to the track name, and says "Channel n"
    /// only when the file offers neither. Never guesses an instrument from the note range.
    public var label: String {
        if let first = instruments.first { return first.name }
        if let name = trackNames.first, !name.isEmpty { return name }
        return isPercussion ? "Percussion" : "Channel \(number + 1)"
    }
}
