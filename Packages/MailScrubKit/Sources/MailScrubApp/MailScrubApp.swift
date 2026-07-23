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
            let path = NSString(string: "~/mailscrub-exception.log").expandingTildeInPath
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
            FileHandle.standardError.write(Data(text.utf8))
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

@main
struct MailScrubApp: App {
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
            .alert("MailScrub uses your Keychain", isPresented: $showKeychainInfo) {
                Button("Continue") {
                    keychainInfoShown = true
                    Task { await model.start() }
                }
            } message: {
                Text("MailScrub stores your Gmail app password in the macOS Keychain so you don't have to re-enter it. macOS may ask you to allow MailScrub to use it — that's expected. Choose \u{201C}Always Allow\u{201D} so you're not asked again.")
            }
            // Gate the first Keychain access behind the explanation; afterwards
            // start directly.
            .task {
                if keychainInfoShown {
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
