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
    /// Non-nil while the result step is up, holding what it is the result *of*.
    /// A Bool used to be enough because only a confirmed unsubscribe reached this
    /// step; a declined attempt now does too, and the two must not read alike
    /// (TASK-57).
    @State private var result: BacklogOffer.Context?

    init(model: AppModel, target: AppModel.ManualUnsubscribe) {
        self._model = Bindable(model)
        self._current = State(initialValue: target)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let result {
                resultStep(result)
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
        guard recorded else {
            askOutcome = true
            return
        }
        // Closing on the result step leaves the backlog question unanswered —
        // "not now" rather than "keep them". The toast is the fallback for that
        // one exit, and only for it: re-offering after an explicit Keep Messages
        // would be the nag this task exists to remove, not a second chance.
        if let result, offer(result) != nil {
            model.offerBacklogDelete(current.id, context: result)
        }
        dismiss()
    }

    /// The sender's page said it worked.
    ///
    /// Recorded straight away, before the backlog question is asked: the
    /// unsubscribe is the fact, and deleting the mail is a separate offer the
    /// user may decline or never answer.
    private func confirm() {
        recorded = true
        detectedConfirmation = false
        model.recordManual(current.id, outcome: .confirmed, offerDelete: false)
        model.recordBrowserOutcome(current.id, .confirmed)
        // The delete offer used to be a twelve-second toast in the status bar
        // while attention was on the sheet closing (TASK-23). It belongs in the
        // interaction that just happened.
        let context: BacklogOffer.Context = current.isEscalation ? .escalated : .unsubscribed
        if offer(context) != nil || current.queue != nil {
            result = context
        } else {
            advance()
        }
    }

    /// Anything that is not a confirmed unsubscribe.
    private func record(_ outcome: BrowserQueue.Outcome) {
        recorded = true
        detectedConfirmation = false
        guard outcome == .couldNotUnsubscribe else {
            // Skipped: looked at and not answered. Nothing happened to this
            // sender, so nothing is recorded against it.
            model.recordBrowserOutcome(current.id, outcome)
            advance()
            return
        }
        // Still an attempt, and the record is what stops the app offering the
        // same automated path again — but recorded as `.failed`, so it does not
        // claim an unsubscribe that did not happen and does not move the sender
        // out of the working list (TASK-57).
        model.recordManual(current.id, outcome: .failed, offerDelete: false)
        model.recordBrowserOutcome(current.id, outcome)
        // The login wall is the moment ignoring or trashing this sender is
        // obviously the next thing to do, so offer it here rather than leaving
        // the user to find the sender again afterwards.
        if offer(.couldNotUnsubscribe) != nil {
            result = .couldNotUnsubscribe
        } else {
            advance()
        }
    }

    /// On to the next queued sender, or out.
    private func advance() {
        result = nil
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
    private func resultStep(_ context: BacklogOffer.Context) -> some View {
        let failed = context == .couldNotUnsubscribe
        return VStack(spacing: 18) {
            Spacer()
            Image(systemName: failed ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .font(.system(size: 44)).foregroundStyle(failed ? .orange : .green)
            Text(
                failed
                    ? "Still subscribed to \(current.name)"
                    : "Unsubscribed from \(current.name)"
            ).font(.title3.weight(.semibold))

            if let offer = offer(context) {
                Text(offer.question).font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(width: 420)
                HStack(spacing: 10) {
                    Button(offer.declineLabel) { advance() }
                    Button(offer.acceptLabel) {
                        // Captured now: `advance` swaps `current` underneath.
                        let id = current.id
                        let accept = offer.accept
                        advance()
                        // No second confirmation: the button above named the
                        // count and where the mail goes, which is what the
                        // Settings trash dialog exists to say
                        // (`BacklogOffer.namesWhatItWillDo`).
                        Task {
                            switch accept {
                            case .trash: await model.deleteMessages(for: [id])
                            case .trashAndIgnore: await model.trashAndIgnore(id)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Text(BacklogOffer.nothingToClear)
                    .font(.callout).foregroundStyle(.secondary)
                Button((current.queue?.remaining ?? 0) > 0 ? "Next Sender" : "Done") { advance() }
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The backlog question for the sender on screen, or nil when they have no
    /// mail left to clear.
    private func offer(_ context: BacklogOffer.Context) -> BacklogOffer? {
        BacklogOffer(
            senderName: current.name,
            messageCount: current.messageCount,
            context: context)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if result != nil, let queue = current.queue, queue.remaining > 0 {
                Label(
                    "\(queue.remaining) more sender\(queue.remaining == 1 ? "" : "s") to go",
                    systemImage: "list.bullet")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let queue = current.queue, result == nil {
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
            if result == nil {
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
