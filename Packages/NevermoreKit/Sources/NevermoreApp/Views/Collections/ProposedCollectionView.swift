import SwiftUI
import NevermoreKit

/// The Proposed collection (TASK-45): what an external agent has put forward,
/// waiting for a human to look at it.
///
/// A collection rather than a sheet, deliberately. A sheet is modal, blocks the
/// rest of the app while the one thing you want is to go and check a sender, and
/// cannot use the keyboard triage the app already has. This is an ordinary list
/// with the ordinary selection, so ⌘A, shift-click, j/k, u, i and d all work as
/// they do everywhere else.
///
/// **The reason is in the row, not the inspector.** Reviewing twenty-five rows
/// without seeing why each was picked is rubber-stamping rather than review, and
/// the agent's reason is the only thing that makes its judgement checkable.
struct ProposedCollectionView: View {
    @Bindable var model: AppModel
    var onUnsubscribe: (Set<GroupID>) -> Void
    var onUnsubscribeAndDelete: (Set<GroupID>) -> Void
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        let rows = model.proposedRows
        if rows.isEmpty {
            // Only reachable with a search active: with no proposal at all the
            // sidebar row doesn't exist and the model has moved on.
            EmptyStateView(
                systemImage: "magnifyingglass",
                title: "No proposed senders match \u{201C}\(model.searchText)\u{201D}",
                message: "Clear the search to see the whole proposal.",
                actionTitle: "Clear Search", action: { model.searchText = "" })
        } else {
            VStack(spacing: 0) {
                banner
                List(selection: $model.selection) {
                    ForEach(rows) { row in
                        self.row(row)
                    }
                }
                .focused($isFocused)
                .selectionKeyboard(
                    model: model,
                    onUnsubscribe: onUnsubscribe,
                    onUnsubscribeAndDelete: onUnsubscribeAndDelete)
            }
        }
    }

    // MARK: - Banner

    /// Says who proposed this, when, and what it is — and offers the way out.
    ///
    /// Dismiss is here rather than only in a menu because declining is a first
    /// -class answer: a proposal the user disagrees with should be as easy to
    /// throw away as it is to act on, or the easy path becomes agreeing with it.
    @ViewBuilder
    private var banner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(Tokens.brandBlue)
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.callout).foregroundStyle(.secondary)
                if let summary = model.proposal?.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.callout).foregroundStyle(.secondary).italic()
                }
                Text("Nothing has happened to these senders. Act on the ones you agree with, remove the ones you don't, and dismiss the rest.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Button("Remove from Proposal") {
                    model.removeFromProposal(model.selection)
                }
                .disabled(model.selectedCount == 0)
                .help("Take the selected senders out of the proposal. Nothing else changes.")
                Button("Dismiss Proposal") { model.dismissProposal() }
                    .help("Clear the whole proposal. No sender is unsubscribed, ignored or trashed.")
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.brandBlue.opacity(0.07))
    }

    private var headline: String {
        guard let proposal = model.proposal else { return "" }
        let n = proposal.items.count
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return "An agent proposed \(n) sender\(n == 1 ? "" : "s") "
            + f.localizedString(for: proposal.createdAt, relativeTo: Date())
            + " — review before acting."
    }

    // MARK: - Recommendation

    /// What the agent means, at the head of the row and in words.
    ///
    /// Colour carries no meaning on its own here — the word is always there —
    /// because the distinction that matters (unsubscribe versus not) has to
    /// survive both Dark Mode and colour-blindness.
    private func recommendationBadge(_ action: RecommendedAction) -> some View {
        HStack(spacing: 4) {
            Image(systemName: action.symbolName)
            Text(action.badgeTitle)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(action == .unsubscribe ? Tokens.brandBlue : .secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(
                (action == .unsubscribe ? Tokens.brandBlue : Color.secondary).opacity(0.12)))
        .frame(width: 108, alignment: .leading)
        // Not "the agent recommends" any more: the app's own reading of the
        // headers can take this slot over (TASK-30), and the line under the
        // reason is what says which of them it was.
        .accessibilityLabel("Recommended: \(action.badgeTitle)")
    }

    // MARK: - Row

    private func row(_ row: AppModel.ProposedRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // The row leads with what the agent means (TASK-52). It used to lead
            // with the unsubscribe method, which said how the app *could*
            // unsubscribe from a sender the agent may well have been asking it
            // not to — the method is still here, next to the count, where it
            // answers a question rather than making a suggestion.
            recommendationBadge(row.recommendation)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).fontWeight(.semibold).lineLimit(1)
                Text(row.email).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 190, alignment: .leading)

            // The agent's words, verbatim, in the widest part of the row — and
            // in the primary colour at body size, because this is the only thing
            // that makes the agent's judgement checkable and it was being read
            // as a caption and skipped (TASK-52). Three lines rather than two:
            // the reasons that matter are the ones arguing against the obvious
            // action, and those are the long ones.
            VStack(alignment: .leading, spacing: 3) {
                Text(row.reason)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .help(row.reason)

                // Only when the app overrode the agent (TASK-30). Under the
                // agent's reason rather than instead of it: the badge above says
                // what to do, and these two lines say who thought so — the
                // agent's judgement stays checkable even when it lost.
                if let note = row.providerNote {
                    Label(note, systemImage: "exclamationmark.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    if let sender = row.sender {
                        Text("\(sender.count) msgs · \(sender.relativeAge)")
                            .font(.caption).foregroundStyle(.secondary)
                        MethodIcon(method: sender.method, size: 14)
                    } else {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.secondary)
                        Text("No messages left")
                            .font(.caption).foregroundStyle(.secondary)
                            .help("This sender's messages are no longer in the mailbox.")
                    }
                }
                HStack(spacing: 6) {
                    // Doing what was recommended is the one-click path; anything
                    // else is a keystroke or a menu away, and an unsubscribe
                    // against a recommendation stops to ask.
                    Button(row.recommendation.buttonTitle) {
                        model.actOnRecommendation(row.id, onUnsubscribe: onUnsubscribe)
                    }
                    .controlSize(.small)
                    .disabled(row.sender == nil)
                    .help(
                        (row.providerNote == nil
                            ? "What the agent recommended for this sender: "
                            : "What Nevermore recommends for this sender: ")
                            + row.recommendation.guidance + ".")
                    Button("Remove") { model.removeFromProposal([row.id]) }
                        .controlSize(.small)
                        .help("Take this sender out of the proposal. Nothing else changes.")
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Remove from Proposal") { model.removeFromProposal([row.id]) }
            if row.sender != nil {
                Divider()
                Button("View Latest Message") { model.viewLatestMessage(row.id) }
            }
            Button("Copy Sender Address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(row.email, forType: .string)
            }
            Divider()
            Button("Dismiss Whole Proposal") { model.dismissProposal() }
        }
    }
}
