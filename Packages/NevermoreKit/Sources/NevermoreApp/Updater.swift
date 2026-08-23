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

        /// Sparkle's own scheduling switch — the same one its first-launch
        /// prompt writes. Reading and writing it through the updater rather
        /// than through `UserDefaults` matters: Sparkle owns the
        /// `SUEnableAutomaticChecks` default, distinguishes "never answered"
        /// from "answered no", and reschedules its background check when the
        /// value changes. Setting the default behind its back would leave the
        /// checkbox and the scheduler disagreeing.
        var automaticallyChecksForUpdates: Bool {
            get { controller.updater.automaticallyChecksForUpdates }
            set { controller.updater.automaticallyChecksForUpdates = newValue }
        }
    }

    /// The Settings ▸ General section for automatic update checks. An empty
    /// view in builds without Sparkle, so the store build shows no section
    /// header for an updater it does not contain.
    @MainActor
    struct AutomaticUpdatesSection: View {
        @State private var enabled = UpdaterController.shared.automaticallyChecksForUpdates

        var body: some View {
            Section("Software updates") {
                Toggle("Check for updates automatically", isOn: $enabled)
                    .onChange(of: enabled) { _, now in
                        UpdaterController.shared.automaticallyChecksForUpdates = now
                    }
                    // Sparkle's first-launch prompt can answer this after the
                    // view is first built, and the Settings window outlives a
                    // single opening.
                    .onAppear { enabled = UpdaterController.shared.automaticallyChecksForUpdates }
                Text("Nevermore asks GitHub for a small file listing the latest version. Turn this off and it makes no request of its own until you pick Check for Updates… from the Help menu.")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
    /// offer, no menu item to show, and nothing to switch off.
    struct CheckForUpdatesButton: View {
        var body: some View { EmptyView() }
    }

    struct AutomaticUpdatesSection: View {
        var body: some View { EmptyView() }
    }

#endif
