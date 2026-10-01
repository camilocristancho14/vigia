// swift-tools-version: 6.0
// Modified for Vigía from Pulse (Apache-2.0). Sparkle and the macOS 26
// linker stamp are removed so the app builds on the macOS 14 and 15 SDKs.

import PackageDescription

let package = Package(
    name: "Pulse",
    // Required for the localized resources in Sources/Pulse/Resources/*.lproj.
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Pulse", targets: ["Pulse"])
    ],
    targets: [
        .executableTarget(
            name: "Pulse",
            path: "Sources/Pulse",
            resources: [
                .process("Resources")
            ]
        ),
        // Tests the executable target directly rather than through a library
        // split. Pulse is one app, not a framework with an app on top, and
        // carving the app's files into two targets to make them reachable
        // would be a refactor in service of the test runner. SwiftPM has been
        // able to `@testable import` an executable target since Swift 5.5.
        .testTarget(
            name: "PulseTests",
            dependencies: ["Pulse"],
            path: "Tests/PulseTests",
            // Captured provider replies, kept as the files they arrived as so
            // a diff against a changed schema is readable.
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
