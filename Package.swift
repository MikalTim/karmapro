// swift-tools-version:6.1
//
// Karma Pro is split into a portable scanning engine and interchangeable
// front ends:
//
//   KarmaCore    Foundation-only library: parsers, analyzers, detectors,
//                indexes, stores, and the public service layer (service/)
//                that front ends call. Builds on macOS and Linux.
//   KarmaServer  Vapor web server for the browser front end (Web/). Only
//                built when the `WebServer` trait is enabled (the default).
//   karma        Headless command-line front end (JSON output) that also
//                starts the web front end with `--serve`. Builds on macOS
//                and Linux.
//   KarmaAppKit  The original macOS AppKit application. It is NOT a SwiftPM
//                target: `./build.sh` compiles it together with KarmaCore as
//                a single module into "Karma Pro.app" (macOS only).
//
// The AppKit sources live in Sources/KarmaAppKit and are never compiled by
// SwiftPM, so `swift build` / `swift test` work unchanged on Linux.
//
// `swift build --disable-default-traits` builds a karma without the web
// server, which compiles and links no Vapor code.
import PackageDescription

let package = Package(
    name: "KarmaPro",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "KarmaCore", targets: ["KarmaCore"]),
        .executable(name: "karma", targets: ["karma"]),
    ],
    traits: [
        .trait(name: "WebServer", description: "Builds the Vapor web front end into karma (--serve)."),
        .default(enabledTraits: ["WebServer"]),
    ],
    dependencies: [
        // CryptoKit-compatible SHA-256 on platforms without CryptoKit (Linux).
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
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
        .target(
            name: "KarmaServer",
            dependencies: [
                "KarmaCore",
                .product(name: "Vapor", package: "vapor"),
            ],
            path: "Sources/KarmaServer"
        ),
        .executableTarget(
            name: "karma",
            dependencies: [
                "KarmaCore",
                .target(name: "KarmaServer", condition: .when(traits: ["WebServer"])),
            ],
            path: "Sources/karma"
        ),
        .testTarget(
            name: "KarmaCoreTests",
            dependencies: ["KarmaCore"],
            path: "Tests/KarmaCoreTests"
        ),
        .testTarget(
            name: "KarmaServerTests",
            dependencies: [
                .target(name: "KarmaServer", condition: .when(traits: ["WebServer"])),
                .product(name: "XCTVapor", package: "vapor", condition: .when(traits: ["WebServer"])),
            ],
            path: "Tests/KarmaServerTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
