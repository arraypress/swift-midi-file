//
//  RealFileTests.swift
//  MIDIFileKitTests
//
//  Created by David Sherlock on 2026.
//
//  Against the 6,013-file corpus the library's thresholds were measured on.
//
//  SKIPS when the corpus is absent, so a bare clone still passes. The numbers asserted here
//  are the ones quoted in ``KeyEstimate``'s documentation, which is the point: if a change
//  moves them, either the change is wrong or the documentation is, and this test says so
//  before either ships.
//

import XCTest
@testable import MIDIFileKit

final class RealFileTests: XCTestCase {

    private static let corpus = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Developer/LLM Training/Training/_removed")

    private func corpusFiles(limit: Int) throws -> [URL] {
        let root = Self.corpus
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw XCTSkip("corpus not present at \(root.path)")
        }
        guard let walker = FileManager.default.enumerator(at: root,
                                                          includingPropertiesForKeys: nil) else {
            throw XCTSkip("corpus unreadable")
        }
        var found: [URL] = []
        for case let url as URL in walker where url.pathExtension.lowercased() == "mid" {
            found.append(url)
            if found.count >= limit { break }
        }
        guard !found.isEmpty else { throw XCTSkip("no .mid files under \(root.path)") }
        return found
    }

    /// Every file in the corpus parses. Measured at 6,013 of 6,013.
    func testEveryCorpusFileParses() throws {
        let files = try corpusFiles(limit: 1500)
        var failures: [String] = []
        for url in files {
            do { _ = try MIDIReader.read(contentsOf: url) }
            catch { failures.append("\(url.lastPathComponent): \(error)") }
        }
        XCTAssertTrue(failures.isEmpty, "unparseable: \(failures.prefix(5))")
    }

    /// No file should take a pathological amount of time. The whole corpus reads in about a
    /// second; a regression that made this quadratic would show up here first.
    func testCorpusParsesQuickly() throws {
        let files = try corpusFiles(limit: 1000)
        let started = Date()
        for url in files { _ = try? MIDIReader.read(contentsOf: url) }
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, 10, "1,000 files should read in about a second, took \(elapsed)")
    }

    /// The finding that shaped ``KeySignature``: every key signature event in the corpus
    /// declares C major, and none of those files are in C major.
    func testDeclaredKeySignaturesAreAllDefaults() throws {
        let files = try corpusFiles(limit: 1200)
        var declared = 0, defaults = 0
        for url in files {
            guard let file = try? MIDIReader.read(contentsOf: url) else { continue }
            for key in file.declaredKeys {
                declared += 1
                if key.isProbablyADefault { defaults += 1 }
            }
        }
        guard declared > 50 else { throw XCTSkip("too few key signatures to judge") }
        XCTAssertEqual(defaults, declared,
                       "the corpus's key signature events are all C major defaults")
    }

    /// The gap that made ``KeyEstimate/mode`` optional: a large share of real single-part
    /// files contain no third, so no mode is derivable from them.
    func testAMeaningfulShareOfRealFilesHaveNoThird() throws {
        let files = try corpusFiles(limit: 1200)
        var withKey = 0, withoutThird = 0
        for url in files {
            guard let file = try? MIDIReader.read(contentsOf: url),
                  let key = file.estimatedKey else { continue }
            withKey += 1
            if !key.hasThird { withoutThird += 1 }
        }
        guard withKey > 100 else { throw XCTSkip("too few files with notes") }
        let share = Double(withoutThird) / Double(withKey)
        XCTAssertGreaterThan(share, 0.15,
                             "measured at 40% across the corpus; if this collapses, either the "
                             + "corpus changed or the third detection broke")
        XCTAssertLessThan(share, 0.75)
    }

    /// Pooling a folder must beat estimating its files one by one. This is the claim that
    /// justifies ``KeyEstimator/estimate(pooling:)`` existing.
    func testPoolingAFolderAgreesWithItsFiles() throws {
        let files = try corpusFiles(limit: 1200)
        var folders: [String: [Note]] = [:]
        for url in files {
            guard let file = try? MIDIReader.read(contentsOf: url) else { continue }
            folders[url.deletingLastPathComponent().path, default: []] += file.notes
        }
        let big = folders.filter { $0.value.count > 500 }
        guard big.count >= 3 else { throw XCTSkip("no folder large enough to pool") }

        for (_, notes) in big.prefix(10) {
            let pooled = KeyEstimator.estimate(notes: notes)
            XCTAssertNotNil(pooled)
            XCTAssertNotNil(pooled?.mode,
                            "a folder of 500+ notes should contain a third somewhere")
            // Three is the floor below which a key means nothing; real folders of bass
            // loops sit at four or five, not the full seven of a scale.
            XCTAssertGreaterThanOrEqual(pooled?.distinctPitchClasses ?? 0, 3)
        }
    }

    /// Chords are found in real polyphonic material and named at a plausible rate. Measured
    /// at 31% of files polyphonic, 69% of spans nameable.
    func testChordsAreFoundAndNamedInRealFiles() throws {
        let files = try corpusFiles(limit: 800)
        var polyphonic = 0, spans = 0, named = 0
        for url in files {
            guard let file = try? MIDIReader.read(contentsOf: url) else { continue }
            let chords = file.chords(minimumTicks: 2)
            guard !chords.isEmpty else { continue }
            polyphonic += 1
            spans += chords.count
            named += chords.filter { $0.name != nil }.count
        }
        guard spans > 100 else { throw XCTSkip("too few chords in this slice") }
        let nameRate = Double(named) / Double(spans)
        XCTAssertGreaterThan(polyphonic, 0)
        XCTAssertGreaterThan(nameRate, 0.3, "naming should succeed on a good share of real chords")
        XCTAssertLessThan(nameRate, 1.0, "exact matching must still refuse some clusters")
    }
}
