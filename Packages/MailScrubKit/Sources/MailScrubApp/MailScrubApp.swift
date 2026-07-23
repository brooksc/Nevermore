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

    var body: some View {
        MainWindowView(model: model)
            .sheet(isPresented: $showOnboarding) {
                OnboardingSheet(model: model) { showOnboarding = false }
                    .interactiveDismissDisabled(model.accounts.isEmpty)
            }
            .onChange(of: model.needsOnboarding, initial: true) { _, needs in
                showOnboarding = needs
            }
    }
}
