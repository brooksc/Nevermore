import AppKit
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
        /// `authRelated` separates "the server rejected this credential" from
        /// "the network fell over": only the first is worth answering with
        /// app-password guidance.
        case failed(String, authRelated: Bool)
    }

    /// The provider auto-detected from the typed domain, if any.
    private var detectedProvider: MailProvider? {
        email.contains("@") ? MailProvider.detect(forEmail: email) : nil
    }

    /// The provider we'll actually connect with: for a re-auth, the one already
    /// stored for that account (a custom domain's provider was picked when the
    /// account was added, and nothing about the address reveals it a second
    /// time); otherwise the detected domain, else the manually-picked one.
    private var provider: MailProvider {
        if let account = reauthAccount {
            return MailProvider.resolved(
                forEmail: account, storedID: model.storedProviderID(for: account))
        }
        return detectedProvider ?? MailProvider.byID(manualProviderID) ?? .gmail
    }

    /// Whether the user must pick a provider (an email with an unrecognized
    /// domain). Never on a re-auth: that account's provider is already stored,
    /// and the picker would be ignored.
    private var needsManualProvider: Bool {
        reauthAccount == nil && email.contains("@") && detectedProvider == nil
    }

    /// App-password guidance for the provider we'd connect with. All the wording
    /// and every URL come from the kit, so they're testable and so the help page
    /// itself can be corrected on the site without shipping a build.
    private var guide: AppPasswordGuide { AppPasswordGuide.forProvider(provider) }

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
                // Only some providers gate app passwords behind 2FA. Telling a
                // Fastmail user to turn on two-factor first is a step they don't
                // need and a reason to give up before starting.
                if guide.requiresTwoFactor {
                    step(1, "Turn on two-factor authentication for your \(provider.displayName) account — it won't issue an app password until you do.")
                }
                let createStep = guide.requiresTwoFactor ? 2 : 1
                step(createStep) {
                    if let url = guide.createURL {
                        HStack(spacing: 4) {
                            // The provider's own noun for it: someone searching
                            // Apple's settings for "app password" finds nothing.
                            Text("Create an \(guide.credentialName.lowercased()) at")
                            Link(url.host ?? url.absoluteString, destination: url)
                        }
                    } else {
                        Text("Create an app password in your \(provider.displayName) security settings.")
                    }
                }
                step(createStep + 1, "Enter it below. Spaces are fine — we'll handle them.")

                Link(destination: guide.helpPageURL) {
                    Label(
                        "Step-by-step guide for \(provider.displayName)",
                        systemImage: "questionmark.circle")
                }
                .padding(.leading, 27)  // aligns with the step text, not the numbers
            }
            .font(.callout)

            Form {
                TextField("Email", text: $email, prompt: Text("you@example.com"))
                    .textContentType(.username)
                    .lineLimit(1)
                    .disabled(reauthAccount != nil)  // fixed when re-authenticating
                if needsManualProvider {
                    Picker("Provider", selection: $manualProviderID) {
                        ForEach(MailProvider.known) { p in
                            Text(p.displayName).tag(p.id)
                        }
                    }
                    .help("We didn't recognize this domain. Choose the service that hosts your mail (e.g. a custom domain on Google Workspace uses Gmail).")
                }
                // lineLimit(1) matters more than it looks: with `fixedSize`
                // below, the field takes its *ideal* height, and a SecureField
                // reports a wrapped multi-line ideal once the content is wider
                // than the field — which is why a long app password inflated it.
                SecureField("App password", text: $password,
                    prompt: Text("xxxx xxxx xxxx xxxx"))
                    .lineLimit(1)
            }
            // Without this the Form takes every point of height the sheet will
            // give it and hands it to the last field, so the password box
            // renders as a ~400pt empty rectangle.
            .fixedSize(horizontal: false, vertical: true)
            .disabled(phase == .validating)

            Label(
                "Saved securely in your macOS Keychain — never written to disk in the clear.",
                systemImage: "lock.fill"
            )
            .font(.caption).foregroundStyle(.secondary)

            // Offered before the password field is filled in, on purpose: the
            // point of the demo is to see what the app does *before* deciding
            // whether to hand it a credential.
            if reauthAccount == nil {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "theatermasks.fill")
                        .foregroundStyle(Tokens.demoAccent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Not ready to sign in?").font(.callout.weight(.medium))
                        Text("Explore a sample mailbox first. No account needed.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Try the Demo") {
                        Task {
                            await model.enterDemoMode()
                            onDone()  // nothing else dismisses this sheet
                        }
                    }
                }
            }

            if case .validating = phase {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Verifying with \(provider.displayName)…").foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            if case .failed(let message, let authRelated) = phase {
                VStack(alignment: .leading, spacing: 6) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    // A rejected credential is far more often the account
                    // password than a mistyped app password, and the server
                    // reports both identically — so name the likely cause
                    // instead of leaving "authentication failed" to be guessed at.
                    if authRelated {
                        Text(guide.authFailureExplanation)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Link(destination: guide.helpPageURL) {
                            Label(
                                "How to create one for \(provider.displayName)",
                                systemImage: "questionmark.circle")
                        }
                    }
                }
                .font(.callout)
            }

            HStack {
                // With no account there's nothing behind this sheet to go back
                // to, and dismissal is disabled — so without this the only way
                // out of a first run is Force Quit.
                if model.accounts.isEmpty {
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut(.cancelAction)
                } else {
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
            // `provider` already resolves re-auth to the account's stored one.
            try await model.addAccount(email: email, appPassword: password, provider: provider)
            onDone()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            let authRelated: Bool
            if case MailBackendError.authenticationFailed = error { authRelated = true }
            else { authRelated = false }
            phase = .failed(message, authRelated: authRelated)
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
