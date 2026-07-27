import SwiftUI
import AppKit

/// Forces the app to run as a regular foreground app. A SwiftPM-built executable
/// (even wrapped in a .app bundle) can otherwise launch as an accessory whose
/// window never comes to front. A real Xcode app target wouldn't need this.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Capture uncaught ObjC exceptions (e.g. AppKit layout aborts) with their
        // reason string, which crash reports omit. Written before the process dies.
        NSSetUncaughtExceptionHandler { exception in
            let text = """
                UNCAUGHT: \(exception.name.rawValue)
                REASON: \(exception.reason ?? "nil")
                STACK:
                \(exception.callStackSymbols.joined(separator: "\n"))
                """
            // Application Support resolves inside the App Sandbox container, so
            // this is writable in a MAS build (unlike a real ~/ path would be).
            if let dir = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            ).appendingPathComponent("Nevermore", isDirectory: true) {
                try? FileManager.default.createDirectory(
                    at: dir, withIntermediateDirectories: true)
                try? text.write(
                    to: dir.appendingPathComponent("last-exception.log"),
                    atomically: true, encoding: .utf8)
            }
            FileHandle.standardError.write(Data(text.utf8))
        }
        // No tab bar: tabs exist to gather many documents, and this app has one
        // window showing one mailbox. Leaving it on put "Show Tab Bar" and
        // "Show All Tabs" at the top of the View menu, above the app's own
        // commands, for a feature that does nothing useful here.
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

@main
struct NevermoreApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .frame(
                    minWidth: Tokens.Metric.windowMinWidth,
                    minHeight: Tokens.Metric.windowMinHeight)
        }
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView(model: model)
        }
    }
}

/// Chooses onboarding vs. the main window based on whether an account exists.
struct RootView: View {
    @Bindable var model: AppModel
    @State private var showOnboarding = false
    /// One-time explanation shown before the app first touches the Keychain, so
    /// the macOS "allow access" prompt isn't a surprise.
    @AppStorage("keychainInfoShown") private var keychainInfoShown = false
    @State private var showKeychainInfo = false
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        MainWindowView(model: model)
            .preferredColorScheme(colorScheme)
            .sheet(isPresented: $showOnboarding) {
                // In add-account mode (a second account) there's no reauth target.
                OnboardingSheet(
                    model: model,
                    reauthAccount: model.wantsToAddAccount ? nil : model.reauthAccount
                ) {
                    showOnboarding = false
                    model.wantsToAddAccount = false
                }
                .interactiveDismissDisabled(model.accounts.isEmpty)
            }
            .onChange(of: model.needsOnboarding, initial: true) { _, needs in
                if needs { showOnboarding = true }
            }
            .onChange(of: model.wantsToAddAccount) { _, wants in
                if wants { showOnboarding = true }
            }
            .sheet(isPresented: $showKeychainInfo) {
                // Opting out (the checkbox) is the only thing that suppresses this
                // for good, so a stray dismissal can't disable the warning.
                KeychainInfoSheet { dontShowAgain in
                    if dontShowAgain { keychainInfoShown = true }
                    showKeychainInfo = false
                    Task { await model.start() }
                }
                .interactiveDismissDisabled()
            }
            // Gate Keychain access behind the explanation — but only when macOS
            // is actually going to ask. On a first run there's no saved item to
            // read (onboarding writes one, which never prompts), and on a normal
            // relaunch this build is already on the item's ACL. Showing it
            // regardless meant a first-run user got an explanation of a dialog
            // they'd never see — and got it *after* onboarding, since both
            // sheets competed for the same presentation slot.
            .task {
                if keychainInfoShown || !model.expectsKeychainPrompt {
                    await model.start()
                } else {
                    showKeychainInfo = true
                }
            }
    }

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil  // follow the system
        }
    }
}
