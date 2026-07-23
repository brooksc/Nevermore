import SwiftUI
import WebKit
import MailScrubKit

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

            Button("Done") { dismiss() }
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
                model.recordManual(target.id, confirmed: false)
                dismiss()
            }
            Button("Mark Unsubscribed") {
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
        webView.customUserAgent = "Mozilla/5.0 (Macintosh) MailScrub/1.0"
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
