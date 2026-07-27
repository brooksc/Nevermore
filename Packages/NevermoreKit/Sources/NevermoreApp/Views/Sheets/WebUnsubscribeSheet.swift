import SwiftUI
import WebKit
import NevermoreKit

/// In-app browser for manual unsubscribes (design 1i).
///
/// Used when the automated request can't be trusted — either the sender only
/// offers a web page that needs a human click, or an earlier automated attempt
/// failed to stick and the sender reappeared. Runs in a non-persistent data
/// store so it never reads or writes the user's real browser cookies.
struct WebUnsubscribeSheet: View {
    @Bindable var model: AppModel
    let target: AppModel.ManualUnsubscribe
    @Environment(\.dismiss) private var dismiss

    @State private var copied = false
    /// Whether an outcome was recorded before this sheet closed.
    @State private var recorded = false
    /// Asking, at the moment of closing, whether the unsubscribe worked.
    @State private var askOutcome = false
    /// Set when the loaded page looks like a successful-unsubscribe confirmation.
    @State private var detectedConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ZStack(alignment: .top) {
                WebView(url: target.url) { detectedConfirmation = true }
                if detectedConfirmation { confirmationBanner }
            }
            Divider()
            footer
        }
        .frame(width: 900, height: 700)
        // Without this SwiftUI dismisses the sheet on Escape itself, before
        // onExitCommand runs — so the sheet closed and nothing was ever
        // recorded. Every exit now routes through close().
        .interactiveDismissDisabled()
        .onExitCommand { close() }
        .confirmationDialog(
            "Did you unsubscribe from \(target.name)?",
            isPresented: $askOutcome, titleVisibility: .visible
        ) {
            Button("Yes, and Delete Their Messages") {
                recorded = true
                model.recordManualAndDelete(target.id)
                dismiss()
            }
            Button("Yes") {
                recorded = true
                model.recordManual(target.id, confirmed: true)
                dismiss()
            }
            Button("Not Yet", role: .cancel) { dismiss() }
        } message: {
            Text("Nevermore can't tell whether the sender accepted it, so it records what you say happened.")
        }
    }

    /// Closing is not itself an answer, so ask — at the moment of closing,
    /// which is when the user knows it.
    ///
    /// This was a status-bar toast, which was too weak: it sat at the bottom of
    /// the window for twelve seconds while the user was looking at the list,
    /// and closing the sheet felt like it should have been the answer.
    private func close() {
        if recorded {
            dismiss()
        } else {
            askOutcome = true
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Unsubscribe — \(target.name)").font(.headline)
                HStack(spacing: 6) {
                    Text(target.url.host ?? "").font(.caption).foregroundStyle(.secondary)
                    Text("· private session").font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()

            // The alias this mail was delivered to, with one-tap copy — for
            // sender pages that ask you to confirm your address.
            if !target.deliveredTo.isEmpty {
                HStack(spacing: 6) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("Delivered to").font(.caption2).foregroundStyle(.secondary)
                        Text(target.deliveredTo).font(.caption.monospaced())
                    }
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(target.deliveredTo, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .help("Copy \(target.deliveredTo)")
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }

            // A sheet is not a window, so Cmd-W never reached it; and the
            // embedded web view swallows key events, so Escape didn't either.
            // Bind both explicitly.
            Button("Done") { close() }
                .keyboardShortcut("w", modifiers: .command)
        }
        .padding(12)
    }

    /// Surfaced when the page auto-detects as a confirmation (design 1i).
    private var confirmationBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            Text("This page looks like a confirmation. Mark this unsubscribe as confirmed?")
                .font(.callout)
            Spacer()
            Button("Not Yet") { detectedConfirmation = false }
                .controlSize(.small)
            Button("Mark Confirmed") {
                recorded = true
                model.recordManual(target.id, confirmed: true)
                dismiss()
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.green.opacity(0.4)))
        .padding(12)
        .shadow(radius: 8, y: 2)
    }

    private var footer: some View {
        HStack {
            if target.isEscalation {
                Label("Automated unsubscribe didn't stick — finish it here.",
                    systemImage: "arrow.uturn.forward")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Text("Complete the unsubscribe on the sender's page, then mark the result.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Couldn't Unsubscribe") {
                recorded = true
                model.recordManual(target.id, confirmed: false)
                dismiss()
            }
            Button("Mark Unsubscribed") {
                recorded = true
                model.recordManual(target.id, confirmed: true)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
    }
}

/// A WKWebView with a non-persistent data store that watches for a
/// confirmation-looking page and reports it back.
private struct WebView: NSViewRepresentable {
    let url: URL
    let onLikelyConfirmation: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onLikelyConfirmation) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()  // isolate from the real browser
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh) \(AppVersion.userAgent)"
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onLikelyConfirmation: () -> Void
        private var alreadyReported = false

        init(_ onLikelyConfirmation: @escaping () -> Void) {
            self.onLikelyConfirmation = onLikelyConfirmation
        }

        /// Hold the browser to the same rule as the HTTP engine.
        ///
        /// This sheet opens a URL taken from a `List-Unsubscribe` header — the
        /// same attacker-authored input `DestinationGuard` exists to contain —
        /// but it previously navigated anywhere the page asked, including
        /// `http://192.168.x.x` admin panels and non-http schemes. Guarding only
        /// the silent request path left the visible one wide open.
        func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
            else {
                Log.unsubscribe.detail("browser blocked non-http navigation: \(url.scheme ?? "?")")
                return .cancel
            }
            // getaddrinfo blocks; keep it off the main actor.
            let allowed = await Task.detached { DestinationGuard.isAllowed(url) }.value
            if !allowed {
                Log.unsubscribe.problem(
                    "browser blocked navigation to non-public host: \(url.host ?? "?")")
            }
            return allowed ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !alreadyReported else { return }
            // Read the visible text and test it (plus the URL) against common
            // "you've been unsubscribed" confirmation phrasings. Heuristic by
            // nature — the user still confirms; this just surfaces the prompt.
            webView.evaluateJavaScript("document.body ? document.body.innerText : ''") {
                [weak self] result, _ in
                guard let self else { return }
                let haystack = (result as? String ?? "") + " " + (webView.url?.absoluteString ?? "")
                if UnsubscribeEngine.looksLikeConfirmation(haystack) {
                    self.alreadyReported = true
                    self.onLikelyConfirmation()
                }
            }
        }
    }
}
