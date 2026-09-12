# swift-midi-file

Read Standard MIDI Files from Swift — notes, chords, tempo, key, instruments.

A MIDI file records what was played. An audio analyser has to *estimate* pitch and onset from
a waveform and is sometimes wrong; here the pitches, their start times, their lengths and
their velocities are recorded facts you read out of the bytes. Only two things in this
library are interpretation — the key and the chord *names* — and both say so.

```swift
import MIDIFileKit

let file = try MIDIReader.read(contentsOf: url)

file.tempoMap.single?.bpm        // 138.0, or nil if the tempo changes
file.bars                        // 4.0, or nil if the metre changes
file.notes                       // every note, in start order
file.channels.map(\.label)       // ["Acoustic Grand Piano", "Fretless Bass", "Standard Kit"]

// What sounds together — exact, not estimated from a spectrum.
for chord in file.chords() {
    print(chord.startBeats, chord.name ?? "unnamed", chord.pitches.map(\.name))
}

// The key the NOTES are in, not the one the file claims.
if let key = file.estimatedKey {
    print(key.name)              // "F#m" — or "F#" when the mode isn't in the file
    print(key.mode == nil)       // true means no third was present to decide it
}
```

## Measured on 6,013 files

Every number here comes from the shipping code over a corpus of commercial trance and techno
MIDI — 6,013 files whose folders and filenames name a key, so there is ground truth to score
against.

| | |
|---|---|
| Files parsed | **6,013 of 6,013**, no failures, in **0.9 s** |
| Notes read | 468,589 |
| Round trip: read → write → read | **6,013 of 6,013** identical |
| Key root, one file | **77%** (2,403 files) |
| Key root, one folder pooled (20+ files) | **92%** (66 folders) |
| Key root + mode, one file | **37%** (108 files labelled with a mode) |
| Key root + mode, where the file contains a third | **64%** |
| Files with 3+ notes sounding at once | 31% |
| Chord spans that could be named | 69% |

## Two findings that shaped the API

**The key signature in the file is almost always a lie.** Across the corpus, every single key
signature event — *895 of 895* — declared C major. None of those files were in C major. The
DAW writes its default once and nobody ever updates it. So `declaredKeys` is surfaced (you're
entitled to see what the bytes say) and `KeySignature.isProbablyADefault` flags it, but
`estimatedKey` computes the key from the notes and is the field to believe. They are
deliberately different types so neither can be substituted for the other by accident.

**The mode is often not knowable, so it is optional.** 42% of the mode-labelled files contain
*no third at all* — they are basslines and sub parts, and 19 of 108 used a single pitch class.
A bassline playing roots and fifths belongs equally to a major and a minor key; the interval
that separates them is simply not in the data. So `KeyEstimate.mode` is `Mode?` and is `nil`
when the evidence is absent:

```swift
key.name          // "F#" — no mode suffix, because none was determined
key.mode          // nil
key.hasThird      // false — this is why
```

A library that always returned a mode would be wrong most of the time on this corpus while
looking exactly as confident as when it is right. Pooling a folder is the fix, and it works:

```swift
// A pack's loops are individually too thin; fifty of them are not.
let key = KeyEstimator.estimate(pooling: folders.map(\.notes))
```

Pooling raised root accuracy from 77% to 92% and recovered the minor mode in 93% of folders
where per-file estimation was a coin flip. Only pool material that belongs together — two keys
average to a third that neither is in, and a low `correlation` is what gives a mixed folder
away.

**Pooling works on a folder of loops; it does not work on a construction kit.** Measured over
58 kits whose folders name a key: 43–46%, however the stems are filtered. A kit is one song
rather than one key, most of its stems are rhythm triggers on a fixed note (the kick, and often
the bass), and the few melodic ones emphasise chord tones instead of the tonic — one kit's
pluck reads Bm where the kit is Em, B being the fifth. Don't auto-label kits.

**To filter individual files, use `margin`, not `isWellSupported`.** The latter is a guard for
*mode* and makes *roots* worse: 69% against 80% ungated, because it discards one- and
two-pitch-class files, which are the easiest roots to get right. `margin` behaves properly —
81% at 0.10, 87% at 0.15, 90% at 0.20.

## Chords are exact; only the name is interpretation

This is where MIDI beats audio outright. This fleet's own `AudioTimbre` abandoned its chord
namer after it called nine of twenty kick drums "F" — a fundamental and its harmonic series
look exactly like a major triad. Here, which notes overlap in time is read, not inferred.

Naming requires an *exact* match against a quality's interval set, so a set that spells
nothing gets no name rather than the nearest one:

```swift
chord.pitches       // always populated — the recorded fact
chord.name          // "C", "Am7", "C/E", "F#5" — or nil
```

Inversions are written with a slash. A chord with no third is named `5`, not guessed into a
mode.

## Writing

The library writes as well as reads, and ``Composition`` is the door in:

```swift
var song = Composition(bpm: 138)
song.addTrack(name: "Bass", channel: 0) { track in
    track.note("F#2", atBeat: 0, lasting: 0.5)
    track.note("A2",  atBeat: 1, lasting: 0.5)
}
song.addTrack(name: "Pad", channel: 1, program: 48) { track in
    track.chord(["F#4", "A4", "C#5"], atBeat: 0, lasting: 4)
}
try song.build().write(to: url)
```

`build()` returns a `MIDIFile`, so anything you construct can be analysed with the same key
and chord code as a file off disk — which is how the tests check that a progression spells
what it was meant to.

A writer has no 31,250-baud cable to squeeze through, so this one never uses running status
and always emits a real note-off. The output is **1% larger** than the DAW's and unambiguous
to every reader, including careless ones.

**Round-tripped over the whole corpus: 6,013 of 6,013 files come back identical** — same
pitches, same start ticks, same durations, same track names. Two bugs were found that way and
neither would have shown up in a unit test:

- A **zero-length note** made the writer emit that note's own off before its own on (releases
  are ordered before strikes, so one note ending as another begins doesn't read as an overlap).
  The reader was left with an open note that swallowed the next note's off, and every duration
  after it in the track was wrong. Zero-length notes are now widened to one tick.
- An **empty track name** was reported as `""` by the reader and omitted by the writer, so it
  vanished on the round trip. An empty name is now `nil`.

## What it handles

Formats 0, 1 and 2. Running status, including the edge that meta and SysEx events neither set
it nor clear it. Note-off written as a zero-velocity note-on. The same pitch struck again
before release. Notes left unterminated at the end of a track. Tempo maps with changes, and
tick-to-second conversion that walks them rather than scaling by the first. SMPTE division as
well as ticks-per-quarter-note. Unknown chunks, oversized headers, truncated final tracks, and
headers that lie about their own track count.

General MIDI program changes give instrument and family names, with channel 10 correctly read
as a drum *kit* rather than an instrument. Where a file has no program changes — which was
**every file** in the measured corpus — the track name is the instrument, and `Channel.label`
falls back to it: `"Bass Layer 1"`, `"Sub"`, `"303 Acid"`.

> The multi-channel and program-change paths are verified against hand-assembled fixtures, not
> against the corpus: only 4 of the 6,013 files use more than one channel and not one contains
> a program change. They're built to the General MIDI specification. If a real arrangement ever
> contradicts them, the file is right.

## Requirements

macOS 14+ / iOS 17+, Swift 6.2. Foundation only — no framework to wrap, nothing to decode, no
model to load, no network.

## Installation

```swift
.package(url: "https://github.com/arraypress/swift-midi-file.git", from: "0.1.0")
```

## The CLI

[`midi`](https://github.com/arraypress/swift-midi-cli) is this library as a command-line tool.

## License

MIT
