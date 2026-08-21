import Foundation
import ProjectDescription

// The Mac App Store target, and only that. A SwiftPM executable can't carry a
// provisioning profile through App Store validation, so the store needs a real
// Xcode app target — but the DMG channel already works, so this deliberately
// does not touch it: make-app.sh and make-dmg.sh remain the Developer ID path.
//
// The store build must not contain Sparkle (Apple rejects apps that update
// themselves). That isn't enforced here by a flag someone can forget: this
// manifest declares no Sparkle package at all, so `#if canImport(Sparkle)` in
// Sources/NevermoreApp/Updater.swift is false and the updater compiles out.
// Adding Sparkle to this target would take a deliberate edit to this file.

/// Read from the same VERSION file `make-app.sh` uses, so the store build and
/// the DMG can't drift apart. Manifests are compiled and run, so this is an
/// ordinary file read at generate time.
let marketingVersion: String = {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Packages/NevermoreKit/VERSION")
    guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Packages/NevermoreKit/VERSION is missing — it is the single source of the marketing version")
    }
    let version = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !version.isEmpty else { fatalError("Packages/NevermoreKit/VERSION is empty") }
    return version
}()

/// App Store Connect requires a strictly increasing CFBundleVersion per upload.
/// The commit count is what `make-app.sh` uses; CI passes it in rather than
/// shelling out from a manifest. Well inside the store's uint32 limit.
let buildNumber = Environment.buildNumber.getString(default: "1")

/// Manual signing needs the profile's *name*, which only exists once the
/// profile has been created for com.brooksc.nevermore. Left empty, the target
/// uses automatic signing, which is what you want locally — Xcode will create
/// the profile the first time it archives.
let masProfileName = Environment.masProfileName.getString(default: "")

let appInfoPlist: [String: Plist.Value] = [
    "CFBundleName": "Nevermore",
    "CFBundleDisplayName": "Nevermore",
    "CFBundleShortVersionString": .string(marketingVersion),
    "CFBundleVersion": .string(buildNumber),
    "CFBundleExecutable": "Nevermore",
    "CFBundleIconFile": "AppIcon",
    "CFBundlePackageType": "APPL",
    "LSMinimumSystemVersion": "14.0",
    // Required for the store; must match the primary category chosen in App
    // Store Connect. Xcode warns on a build without it.
    "LSApplicationCategoryType": "public.app-category.productivity",
    "NSHighResolutionCapable": true,
    "NSPrincipalClass": "NSApplication",
    // Unsubscribe requests hit arbitrary, user-directed third-party endpoints,
    // some of which publish http-only List-Unsubscribe URLs. ATS blocks those
    // by default. The destinations are chosen by the mail sender, not the app,
    // and reaching them is the app's whole job — see the App Review notes in
    // MAS-RELEASE.md, which explain this to a reviewer along with the SSRF
    // guard that validates every such URL and every redirect hop.
    "NSAppTransportSecurity": ["NSAllowsArbitraryLoads": true],
]

/// Only set when a profile name is supplied; passing a profile to targets that
/// can't take one is how a manually-signed build starts failing in confusing
/// ways. Scoped to the app target for the same reason.
let signingSettings: SettingsDictionary =
    masProfileName.isEmpty
    ? [:]
    : [
        "CODE_SIGN_STYLE": "Manual",
        "CODE_SIGN_IDENTITY": "Apple Distribution",
        "PROVISIONING_PROFILE_SPECIFIER": .string(masProfileName),
    ]

let project = Project(
    name: "Nevermore",
    organizationName: "Benjamin Brooks Cutter",
    options: .options(automaticSchemesOptions: .disabled),
    packages: [
        .local(path: "Packages/NevermoreKit")
    ],
    settings: .settings(
        base: [
            "DEVELOPMENT_TEAM": "SU999VT2G2",
            "SWIFT_VERSION": "6.0",
            "MARKETING_VERSION": .string(marketingVersion),
            "CURRENT_PROJECT_VERSION": .string(buildNumber),
        ],
        configurations: [
            .debug(name: "Debug"),
            .release(name: "Release"),
        ]
    ),
    targets: [
        .target(
            name: "Nevermore",
            destinations: .macOS,
            product: .app,
            bundleId: "com.brooksc.nevermore",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: appInfoPlist),
            // The same sources make-app.sh builds — one app, two packagings,
            // not two copies of the UI.
            sources: ["Packages/NevermoreKit/Sources/NevermoreApp/**"],
            resources: ["Packages/NevermoreKit/Resources/AppIcon.icns"],
            entitlements: "Packages/NevermoreKit/Resources/Nevermore.entitlements",
            dependencies: [
                .package(product: "NevermoreKit")
            ],
            // NEVERMORE_MAS compiles out anything the sandbox cannot run. Today
            // that is the local HTTP server and its Settings section: the
            // entitlements grant `network.client` but not `network.server`, so
            // the listener could not bind, and the stdio bridge that would talk
            // to it is not in this target's sources anyway. SwiftPM never
            // defines this, so the DMG build keeps the feature.
            //
            // (Naming the bridge's product here, even in a comment, trips the
            // test that pins this target to the app's sources alone.)
            settings: .settings(
                base: signingSettings.merging([
                    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) NEVERMORE_MAS"
                ]) { _, new in new }
            )
        )
    ],
    schemes: [
        .scheme(
            name: "Nevermore",
            shared: true,
            buildAction: .buildAction(targets: ["Nevermore"]),
            runAction: .runAction(configuration: "Debug", executable: "Nevermore"),
            archiveAction: .archiveAction(configuration: "Release")
        )
    ]
)
