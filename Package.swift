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

// Swift 7's import rule, today: a file must import every module whose members
// it uses, rather than leaning on another file's imports.
for target in package.targets where target.type != .system && target.type != .binary && target.type != .plugin {
    target.swiftSettings = (target.swiftSettings ?? []) + [.enableUpcomingFeature("MemberImportVisibility")]
}
