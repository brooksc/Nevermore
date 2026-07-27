// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NevermoreKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NevermoreKit", targets: ["NevermoreKit"]),
        .executable(name: "nevermore-probe", targets: ["Probe"]),
        .executable(name: "nevermore-tests", targets: ["NevermoreTests"]),
        .executable(name: "NevermoreApp", targets: ["NevermoreApp"]),
    ],
    dependencies: [
        // SwiftMail 1.8.0 depends on a branch-pinned swift-nio-imap, so SPM rejects
        // a `from:` requirement ("stable-version depends on unstable-version").
        // Pin the exact tag revision instead — reproducible, and revisit on upgrade.
        .package(
            url: "https://github.com/Cocoanetics/SwiftMail.git",
            // Past 1.8.0: PR #192 (merged 2026-07-25) adds fetchGmailAttributes,
            // which is how "view this message" opens the Gmail conversation
            // directly instead of a search result. No tag contains it yet.
            revision: "7ba22114bf681acc105fe728d0130c79a6a51cf0"
        ),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.9.0"),
        // Sparkle powers in-app updates for the Developer ID / DMG build only.
        // The Mac App Store target must not link it — Apple rejects apps that
        // update themselves — which is why it hangs off NevermoreApp rather
        // than NevermoreKit, and why every use of it is behind
        // `#if canImport(Sparkle)`. An Xcode MAS target that omits this package
        // compiles the updater out with no flags to remember.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "NevermoreKit",
            dependencies: [
                .product(name: "SwiftMail", package: "SwiftMail"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // CLI harness: how M1/M2 get verified against a real mailbox without a UI.
        .executableTarget(
            name: "Probe",
            dependencies: ["NevermoreKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Tests are an executable, not a .testTarget: SwiftPM builds test targets
        // as .xctest bundles on macOS, which needs XCTest/_TestingInterop from a
        // full Xcode install. This runs anywhere `swift build` does.
        // Convert to swift-testing when Xcode becomes a hard requirement (M5).
        .executableTarget(
            name: "NevermoreTests",
            dependencies: ["NevermoreKit"],
            path: "Tests/NevermoreTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The SwiftUI app (M5). Built as a plain executable here and wrapped into
        // a .app bundle by make-app.sh; needs full Xcode for the SDK.
        .executableTarget(
            name: "NevermoreApp",
            dependencies: [
                "NevermoreKit",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
