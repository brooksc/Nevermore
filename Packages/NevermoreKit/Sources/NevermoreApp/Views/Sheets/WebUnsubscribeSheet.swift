import SwiftUI
import WebKit
import NevermoreKit

/// In-app browser for manual unsubscribes (design 1i), and the sitting that
/// works a whole queue of them (TASK-47).
///
/// Used when the automated request can't be trusted — either the sender only
/// offers a web page that needs a human click, or an earlier automated attempt
/// failed to stick and the sender reappeared. Runs in a non-persistent data
/// store so it never reads or writes the user's real browser cookies.
///
/// When the sender came from the browser queue the sheet does not close on an
/// answer: it records the outcome and loads the next sender. Thirty senders one
/// at a time, each interleaved with going back to the list and finding the next
/// one, is the part that does not scale — so the sequence lives here, and the
/// user leaves it once.
///
/// **An agent cannot reach any of this.** It can fill the queue and read how far
/// through it the human is; opening a page and saying what happened on it is a
/// person's job by construction (`AgentActions.queueForBrowser`).
struct WebUnsubscribeSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    /// The sender on screen now. Not the one the sheet was opened with: working
    /// a queue swaps this in place rather than closing and reopening.
    @State private var current: AppModel.ManualUnsubscribe
    @State private var copied = false
    /// Whether an outcome was recorded for `current` before it was left.
    @State private var recorded = false
    /// Asking, at the moment of closing, whether the unsubscribe worked.
    @State private var askOutcome = false
    /// Set when the loaded page looks like a successful-unsubscribe confirmation.
    @State private var detectedConfirmation = false
    /// Shown after a confirmed unsubscribe: the backlog offer, and the way on to
    /// the next sender.
    @State private var showingResult = false

    init(model: AppModel, target: AppModel.ManualUnsubscribe) {
        self._model = Bindable(model)
        self._current = State(initialValue: target)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showingResult {
                resultStep
            } else {
                ZStack(alignment: .top) {
                    // Identity by sender: without this the same WKWebView would
                    // be reused across a queue advance and keep showing the
                    // previous sender's page.
                    WebView(url: current.url) { detectedConfirmation = true }
                        .id(current.id)
                    if detectedConfirmation { confirmationBanner }
                }
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
            "Did you unsubscribe from \(current.name)?",
            isPresented: $askOutcome, titleVisibility: .visible
        ) {
            Button("Yes") { confirm() }
            Button("No, I Couldn't") { record(.couldNotUnsubscribe) }
            if current.queue != nil {
                // Leaving one sender unanswered is not leaving the queue. Both
                // exits exist because they mean different things: a skipped
                // sender has been looked at and given up on, and a stopped
                // sitting has entries nobody has seen yet.
                Button("Skip This One") { record(.abandoned) }
                Button("Stop for Now", role: .cancel) { dismiss() }
            } else {
                Button("Not Yet", role: .cancel) { dismiss() }
            }
        } message: {
            Text("Nevermore can't tell whether the sender accepted it, so it records what you say happened.")
        }
    }

    // MARK: - Outcomes

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

    /// The sender's page said it worked.
    ///
    /// Recorded straight away, before the backlog question is asked: the
    /// unsubscribe is the fact, and deleting the mail is a separate offer the
    /// user may decline or never answer.
    private func confirm() {
        recorded = true
        detectedConfirmation = false
        model.recordManual(current.id, confirmed: true, offerDelete: false)
        model.recordBrowserOutcome(current.id, .confirmed)
        // The delete offer used to be a twelve-second toast in the status bar
        // while attention was on the sheet closing (TASK-23). It belongs in the
        // interaction that just happened.
        if current.messageCount > 0 || current.queue != nil {
            showingResult = true
        } else {
            advance()
        }
    }

    /// Anything that is not a confirmed unsubscribe.
    private func record(_ outcome: BrowserQueue.Outcome) {
        recorded = true
        detectedConfirmation = false
        if outcome == .couldNotUnsubscribe {
            // Still an attempt, and the record is what stops the app offering
            // the same automated path again.
            model.recordManual(current.id, confirmed: false)
        }
        model.recordBrowserOutcome(current.id, outcome)
        advance()
    }

    /// On to the next queued sender, or out.
    private func advance() {
        showingResult = false
        guard current.queue != nil, let next = model.nextBrowserTarget() else {
            dismiss()
            return
        }
        current = next
        recorded = false
        detectedConfirmation = false
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Unsubscribe — \(current.name)").font(.headline)
                HStack(spacing: 6) {
                    Text(current.url.host ?? "").font(.caption).foregroundStyle(.secondary)
                    Text("· private session").font(.caption).foregroundStyle(.tertiary)
                    if let queue = current.queue {
                        Text("· \(queue.index) of \(queue.total)")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            Spacer()

            // The alias this mail was delivered to, with one-tap copy — for
            // sender pages that ask you to confirm your address.
            if !current.deliveredTo.isEmpty {
                HStack(spacing: 6) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("Delivered to").font(.caption2).foregroundStyle(.secondary)
                        Text(current.deliveredTo).font(.caption.monospaced())
                    }
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(current.deliveredTo, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .help("Copy \(current.deliveredTo)")
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }

            // A sheet is not a window, so Cmd-W never reached it; and the
            // embedded web view swallows key events, so Escape didn't either.
            // Bind both explicitly.
            Button(current.queue == nil ? "Done" : "Stop for Now") { close() }
                .keyboardShortcut("w", modifiers: .command)
        }
        .padding(12)
    }

    /// Surfaced when the page auto-detects as a confirmation (design 1i).
    ///
    /// It leads to the same result step every other confirmed exit does, so the
    /// happy path is no longer the one where the backlog offer degrades to a
    /// toast that is about to expire (TASK-23).
    private var confirmationBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            Text("This page looks like a confirmation. Mark this unsubscribe as confirmed?")
                .font(.callout)
            Spacer()
            Button("Not Yet") { detectedConfirmation = false }
                .controlSize(.small)
            Button("Mark Confirmed") { confirm() }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.green.opacity(0.4)))
        .padding(12)
        .shadow(radius: 8, y: 2)
    }

    // MARK: - Result step

    /// What to do with the mail that is already here, asked where the user is
    /// looking (TASK-23), and the way on to the next sender (TASK-47).
    private var resultStep: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44)).foregroundStyle(.green)
            Text("Unsubscribed from \(current.name)").font(.title3.weight(.semibold))

            if current.messageCount > 0 {
                Text(backlogQuestion).font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(width: 420)
                HStack(spacing: 10) {
                    Button("Keep Messages") { advance() }
                    Button(deleteLabel) {
                        // Captured now: `advance` swaps `current` underneath.
                        let id = current.id
                        let escalation = current.isEscalation
                        advance()
                        Task {
                            if escalation {
                                await model.trashAndIgnore(id)
                            } else {
                                await model.deleteMessages(for: [id])
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Text("There is no mail left from this sender to clear.")
                    .font(.callout).foregroundStyle(.secondary)
                Button((current.queue?.remaining ?? 0) > 0 ? "Next Sender" : "Done") { advance() }
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var backlogQuestion: String {
        let count = current.messageCount.formatted()
        if current.isEscalation {
            // A sender that already ignored one unsubscribe is the one you most
            // want gone, and this is the wording the Reappeared row uses.
            return "\(current.name) kept mailing after the last unsubscribe. "
                + "\(count) of their messages are still in your mailbox."
        }
        return "\(count) message\(current.messageCount == 1 ? "" : "s") from this sender "
            + "\(current.messageCount == 1 ? "is" : "are") still in your mailbox. "
            + "Deleted mail moves to your provider's Trash."
    }

    private var deleteLabel: String {
        current.isEscalation
            ? "Trash and Ignore"
            : "Delete \(current.messageCount.formatted()) Message"
                + (current.messageCount == 1 ? "" : "s")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if showingResult, let queue = current.queue, queue.remaining > 0 {
                Label(
                    "\(queue.remaining) more sender\(queue.remaining == 1 ? "" : "s") to go",
                    systemImage: "list.bullet")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let queue = current.queue, !showingResult {
                Label(queue.reason.explanation, systemImage: "hand.raised")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            } else if current.isEscalation {
                Label("Automated unsubscribe didn't stick — finish it here.",
                    systemImage: "arrow.uturn.forward")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Text("Complete the unsubscribe on the sender's page, then mark the result.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !showingResult {
                if current.queue != nil {
                    Button("Skip This One") { record(.abandoned) }
                        .help("Leave this sender unanswered and move on. It stays out of the queue.")
                }
                Button("Couldn't Unsubscribe") { record(.couldNotUnsubscribe) }
                Button("Mark Unsubscribed") { confirm() }
                    .buttonStyle(.borderedProminent)
            }
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
