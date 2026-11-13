// swift-tools-version:5.9
//
// Karma Pro is split into a portable scanning engine and interchangeable
// front ends:
//
//   KarmaCore    Foundation-only library: parsers, analyzers, detectors,
//                indexes, stores. Builds on macOS and Linux.
//   karma        Headless command-line front end (JSON output). Builds on
//                macOS and Linux.
//   KarmaAppKit  The original macOS AppKit application. It is NOT a SwiftPM
//                target: `./build.sh` compiles it together with KarmaCore as
//                a single module into "Karma Pro.app" (macOS only).
//
// The AppKit sources live in Sources/KarmaAppKit and are never compiled by
// SwiftPM, so `swift build` / `swift test` work unchanged on Linux.
import PackageDescription

let package = Package(
    name: "KarmaPro",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "KarmaCore", targets: ["KarmaCore"]),
        .executable(name: "karma", targets: ["karma"]),
    ],
    dependencies: [
        // CryptoKit-compatible SHA-256 on platforms without CryptoKit (Linux).
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0"),
    ],
    targets: [
        .target(
            name: "KarmaCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto",
                         condition: .when(platforms: [.linux])),
            ],
            path: "Sources/KarmaCore"
        ),
        .executableTarget(
            name: "karma",
            dependencies: ["KarmaCore"],
            path: "Sources/karma"
        ),
        .testTarget(
            name: "KarmaCoreTests",
            dependencies: ["KarmaCore"],
            path: "Tests/KarmaCoreTests"
        ),
    ]
)
