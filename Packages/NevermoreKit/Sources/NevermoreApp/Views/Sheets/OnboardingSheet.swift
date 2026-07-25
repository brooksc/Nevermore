import SwiftUI
import NevermoreKit

/// Add-account sheet (design 1d): explain → get password → enter, with inline
/// validation. One view, three states, no wizard chrome. Provider-aware: the
/// instructions and app-password link adapt to the detected mail provider, and
/// unknown (custom) domains get a provider picker.
struct OnboardingSheet: View {
    @Bindable var model: AppModel
    /// Non-nil when re-authenticating a saved account whose Keychain item became
    /// unreadable (rather than adding a brand-new account).
    var reauthAccount: String?
    var onDone: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var manualProviderID = MailProvider.gmail.id
    @State private var phase: Phase = .entry

    enum Phase: Equatable {
        case entry
        case validating
        case failed(String)
    }

    /// The provider auto-detected from the typed domain, if any.
    private var detectedProvider: MailProvider? {
        email.contains("@") ? MailProvider.detect(forEmail: email) : nil
    }

    /// The provider we'll actually connect with: detected domain wins, else the
    /// manually-picked one.
    private var provider: MailProvider {
        detectedProvider ?? MailProvider.byID(manualProviderID) ?? .gmail
    }

    /// Whether the user must pick a provider (an email with an unrecognized domain).
    private var needsManualProvider: Bool {
        email.contains("@") && detectedProvider == nil
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
                        ? "Add Your Mail Account" : "Re-enter Your App Password")
                        .font(.title2.weight(.semibold))
                    Text("Nevermore reads message headers only — never bodies — and stores them on this Mac. It signs in with an app-specific password over IMAP.")
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
                step(1, "Turn on two-factor authentication for your \(provider.displayName) account.")
                step(2) {
                    if let url = provider.appPasswordURL {
                        HStack(spacing: 4) {
                            Text("Create an app password at")
                            Link(url.host ?? url.absoluteString, destination: url)
                        }
                    } else {
                        Text("Create an app-specific password in your \(provider.displayName) security settings.")
                    }
                }
                step(3, "Enter it below. Spaces are fine — we'll handle them.")
            }
            .font(.callout)

            Form {
                TextField("Email", text: $email, prompt: Text("you@example.com"))
                    .textContentType(.username)
                    .disabled(reauthAccount != nil)  // fixed when re-authenticating
                if needsManualProvider {
                    Picker("Provider", selection: $manualProviderID) {
                        ForEach(MailProvider.known) { p in
                            Text(p.displayName).tag(p.id)
                        }
                    }
                    .help("We didn't recognize this domain. Choose the service that hosts your mail (e.g. a custom domain on Google Workspace uses Gmail).")
                }
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
                    Text("Verifying with \(provider.displayName)…").foregroundStyle(.secondary)
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
        // Re-auth keeps the account's existing provider; new accounts use the
        // detected/picked one.
        let chosen: MailProvider = {
            if let account = reauthAccount {
                return MailProvider.resolved(
                    forEmail: account, storedID: model.storedProviderID(for: account))
            }
            return provider
        }()
        do {
            try await model.addAccount(email: email, appPassword: password, provider: chosen)
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
