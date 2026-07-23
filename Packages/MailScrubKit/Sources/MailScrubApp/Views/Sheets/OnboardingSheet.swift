import SwiftUI

/// Add-account sheet (design 1d): explain → get password → enter, with inline
/// validation. One view, three states, no wizard chrome.
struct OnboardingSheet: View {
    @Bindable var model: AppModel
    /// Non-nil when re-authenticating a saved account whose Keychain item became
    /// unreadable (rather than adding a brand-new account).
    var reauthAccount: String?
    var onDone: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var phase: Phase = .entry

    enum Phase: Equatable {
        case entry
        case validating
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: reauthAccount == nil
                    ? "envelope.badge.person.crop" : "key.horizontal")
                    .font(.system(size: 32))
                    .foregroundStyle(Tokens.brandBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reauthAccount == nil
                        ? "Add Your Gmail Account" : "Re-enter Your App Password")
                        .font(.title2.weight(.semibold))
                    Text("MailScrub reads message headers only — never bodies — and stores them on this Mac. It signs in with a Gmail app password.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Re-auth: explain *why* this appeared, so it isn't confusing.
            if let account = reauthAccount {
                Label {
                    Text("macOS couldn't unlock the saved password for **\(account)**. This can happen after an app update or if the app was moved. Your local mail library is untouched — just re-enter the app password to reconnect.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.callout)
                .padding(10)
                .background(Tokens.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 8) {
                step(1, "Turn on 2-Step Verification for your Google account.")
                step(2) {
                    HStack(spacing: 4) {
                        Text("Create an app password at")
                        Link("myaccount.google.com/apppasswords",
                            destination: URL(string: "https://myaccount.google.com/apppasswords")!)
                    }
                }
                step(3, "Enter it below. Spaces are fine — we'll handle them.")
            }
            .font(.callout)

            Form {
                TextField("Email", text: $email, prompt: Text("you@gmail.com"))
                    .textContentType(.username)
                    .disabled(reauthAccount != nil)  // fixed when re-authenticating
                SecureField("App password", text: $password,
                    prompt: Text("xxxx xxxx xxxx xxxx"))
            }
            .disabled(phase == .validating)

            Label(
                "Saved securely in your macOS Keychain — never written to disk in the clear.",
                systemImage: "lock.fill"
            )
            .font(.caption).foregroundStyle(.secondary)

            if case .validating = phase {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Verifying with Gmail…").foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            if case .failed(let message) = phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if !model.accounts.isEmpty {
                    Button("Cancel", role: .cancel) { onDone() }
                }
                Spacer()
                Button("Add Account") { Task { await submit() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear { if let account = reauthAccount { email = account } }
    }

    private var canSubmit: Bool {
        phase != .validating
            && email.contains("@")
            && password.replacingOccurrences(of: " ", with: "").count >= 8
    }

    private func submit() async {
        phase = .validating
        do {
            try await model.addAccount(email: email, appPassword: password)
            onDone()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .failed(message)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        step(n) { Text(text) }
    }

    private func step<Content: View>(
        _ n: Int, @ViewBuilder _ content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Tokens.brandBlue))
            content()
        }
    }
}
