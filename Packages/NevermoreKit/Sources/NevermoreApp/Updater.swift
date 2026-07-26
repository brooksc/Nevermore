import SwiftUI

#if canImport(Sparkle)
    import Sparkle

    /// In-app updates for the Developer ID / DMG build.
    ///
    /// Gated on `canImport` rather than a custom build flag: the Mac App Store
    /// target is a separate Xcode target that simply doesn't include the Sparkle
    /// package, so this compiles out with nothing to remember and no way to
    /// accidentally ship an updater into a store build — which Apple rejects.
    ///
    /// `startingUpdater: true` schedules Sparkle's own background check on its
    /// default 24-hour interval. It only acts if `SUFeedURL` and `SUPublicEDKey`
    /// are present in the bundle, so a build made before the signing key exists
    /// is inert rather than broken.
    @MainActor
    final class UpdaterController {
        static let shared = UpdaterController()

        private let controller: SPUStandardUpdaterController

        private init() {
            controller = SPUStandardUpdaterController(
                startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        }

        func checkForUpdates() {
            controller.updater.checkForUpdates()
        }

        var canCheckForUpdates: Bool {
            controller.updater.canCheckForUpdates
        }
    }

    /// The Help-menu item. A no-op stub in builds without Sparkle.
    struct CheckForUpdatesButton: View {
        var body: some View {
            Button("Check for Updates…") { UpdaterController.shared.checkForUpdates() }
                .disabled(!UpdaterController.shared.canCheckForUpdates)
        }
    }

#else

    /// Mac App Store build: updates come from the store, so there is nothing to
    /// offer and no menu item to show.
    struct CheckForUpdatesButton: View {
        var body: some View { EmptyView() }
    }

#endif
