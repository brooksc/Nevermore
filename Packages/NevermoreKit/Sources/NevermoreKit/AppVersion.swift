import Foundation

/// The running build's version, read from the bundle rather than hardcoded.
///
/// See RELEASE.md: `make-app.sh` writes these into `Info.plist`, and nothing in
/// the source should carry a version string of its own.
public enum AppVersion {
    /// Marketing version, e.g. `0.1`. The fallback marks a non-bundled build
    /// (tests, the probe CLI) so it can't be mistaken for a real release.
    public static var marketing: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.0-dev"
    }

    /// Build number, e.g. `47`. Opaque and monotonic.
    public static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// What to show a human: `0.1 (47)`.
    public static var display: String { "\(marketing) (\(build))" }

    /// The `User-Agent` sent on unsubscribe requests. One definition, so the
    /// version we announce can't drift from the version we are — it read
    /// `Nevermore/1.0` in three places while the bundle said 0.1.
    public static var userAgent: String { "Nevermore/\(marketing)" }
}
