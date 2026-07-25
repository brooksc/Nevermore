import SwiftUI

/// Shown once (until dismissed) before Nevermore first touches the Keychain, so
/// the macOS "allow access" prompt isn't a surprise. A styled sheet rather than
/// a stock alert, matching the onboarding sheet.
struct KeychainInfoSheet: View {
    /// Called with whether the user opted out of seeing this again.
    var onContinue: (_ dontShowAgain: Bool) -> Void
    @State private var dontShowAgain = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "key.horizontal.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Tokens.brandBlue)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your password stays in the Keychain")
                        .font(.title3.weight(.semibold))
                    Text("Nevermore saves your app password to the macOS Keychain so you don't have to re-enter it. macOS may ask you to allow access — that's expected. Choose \u{201C}Always Allow\u{201D} so you're not asked again.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            HStack {
                Toggle("Don't show this again", isOn: $dontShowAgain)
                    .toggleStyle(.checkbox)
                    .font(.callout)
                Spacer()
                Button("Continue") { onContinue(dontShowAgain) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 430)
    }
}
