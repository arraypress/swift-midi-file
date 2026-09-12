// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-midi-file",
    // Foundation only. A Standard MIDI File is a byte format from 1988 — there is no
    // framework to wrap, nothing to decode, and no model to load, so this floors at the
    // same macOS as its siblings purely for consistency and would run anywhere Swift does.
    platforms: [
        .macOS(.v14), .iOS(.v17)
    ],
    products: [
        .library(name: "MIDIFileKit", targets: ["MIDIFileKit"]),
    ],
    targets: [
        .target(name: "MIDIFileKit"),
        .testTarget(name: "MIDIFileKitTests", dependencies: ["MIDIFileKit"]),
    ]
)
