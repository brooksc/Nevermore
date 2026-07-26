import SwiftUI

/// What Nevermore does, in the order the user will meet it.
///
/// Shown two ways from one source: `compact` sits on the first-sync screen
/// (where the user has minutes to spare and nothing else to read), and the full
/// version is a sheet from Help ▸ How Nevermore Works. Keeping one definition
/// means the explanation can't drift between the two places.
struct HowItWorksView: View {
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 14 : 20) {
            if !compact {
                Text("How Nevermore Works")
                    .font(.title2.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: compact ? 12 : 16) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    numbered(index + 1, title: step.title, body: step.body)
                }
            }

            if !compact {
                Divider()
                methodLegend
                Divider()
                caveats
            }
        }
        .frame(width: compact ? 460 : 520, alignment: .leading)
    }

    private struct Step { let title: String; let body: String }

    private var steps: [Step] {
        [
            Step(
                title: "It reads headers, not mail",
                body: "Nevermore looks for messages that carry a standard unsubscribe header — nearly all legitimate bulk mail does. It reads the sender, subject, and date; it never downloads a message body, and nothing leaves your Mac."),
            Step(
                title: "Pick a sender, then unsubscribe",
                body: "Senders are grouped so one row covers every message they've sent you. Select one and choose Unsubscribe — optionally trashing their messages at the same time."),
            Step(
                title: "It tries to do it for you",
                body: "Where a sender supports it, Nevermore sends the unsubscribe request directly. Otherwise it opens their page or emails them on your behalf."),
            Step(
                title: "If they keep emailing, you'll know",
                body: "Unsubscribing can't be verified in general, so Nevermore says \u{201C}requested\u{201D} rather than claiming success. If a sender mails again afterwards, they move to Reappeared and you can finish them off by hand in the built-in browser."),
        ]
    }

    private func numbered(_ n: Int, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Tokens.brandBlue))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(body)
                    .font(compact ? .caption : .callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The icons in the list's Unsubscribe column. They carry tooltips, but a
    /// tooltip only helps someone who already suspects there's something to hover.
    private var methodLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What the icons mean").font(.callout.weight(.semibold))
            ForEach([UnsubscribeMethod.oneClick, .webLink, .email, .manual], id: \.systemImage) { method in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    MethodIcon(method: method, size: 14)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(method.inspectorTitle).font(.callout)
                        Text(method.legendDetail)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// The limits, stated plainly. A tool that acts on your mailbox shouldn't
    /// leave the user guessing about what it can't see.
    private var caveats: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What it won't find").font(.callout.weight(.semibold))
            bullet("Senders whose only unsubscribe link is buried in the message body. Finding those would mean reading your mail, which Nevermore doesn't do.")
            bullet("Flagged or starred messages, which are skipped on purpose so your important mail is never in scope.")
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            Text(text)
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

extension UnsubscribeMethod {
    /// Sender-independent version of `inspectorDetail`, for the legend.
    var legendDetail: String {
        switch self {
        case .oneClick: "Sent directly to the sender. Nothing opens."
        case .webLink: "Opens the sender's unsubscribe page — you may need to confirm there."
        case .email: "Sends an unsubscribe email on your behalf."
        case .manual: "No published link. Opens a search for the sender's mail in your webmail."
        }
    }
}

/// Sheet wrapper for Help ▸ How Nevermore Works.
struct HowItWorksSheet: View {
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScrollView { HowItWorksView().padding(.trailing, 4) }
            HStack {
                Spacer()
                Button("Done") { onDone() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 580, height: 620)
    }
}
