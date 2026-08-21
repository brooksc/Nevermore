import NevermoreKit
import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: $model.collection) {
            // Account switcher — only when there's a choice to make.
            if model.accounts.count > 1, let current = model.currentAccount {
                Section("ACCOUNT") {
                    Menu {
                        ForEach(model.accounts, id: \.self) { account in
                            Button {
                                Task { await model.switchAccount(account) }
                            } label: {
                                if account == current {
                                    Label(account, systemImage: "checkmark")
                                } else {
                                    Text(account)
                                }
                            }
                        }
                        Divider()
                        Button("Add Account…") { model.wantsToAddAccount = true }
                    } label: {
                        Label(current, systemImage: "person.crop.circle")
                    }
                }
            }
            ForEach(SenderCollection.Section.allCases) { section in
                // A section with nothing to show isn't drawn — which is how
                // ATTENTION disappears when nobody has reappeared, and how
                // REVIEW stays invisible for the users (most of them) who never
                // connect an agent. The rule per collection lives on the model,
                // so this doesn't name any one of them.
                let visible = section.members.filter(model.shows)
                if !visible.isEmpty {
                    Section(section.rawValue) {
                        ForEach(visible) { item in
                            row(item)
                                .tag(item)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(
            min: Tokens.Metric.sidebarMin,
            ideal: Tokens.Metric.sidebarWidth,
            max: Tokens.Metric.sidebarMax)
    }

    @ViewBuilder
    private func row(_ item: SenderCollection) -> some View {
        let n = model.count(for: item)
        if item == .reappeared || item == .proposed {
            // Reappeared uses an accent pill, not a plain count (design 1a).
            // Proposed takes the same treatment: both are rows that appear
            // because something is waiting on the user, and a plain badge reads
            // as a standing total rather than a queue.
            HStack {
                Label(item.title, systemImage: item.systemImage)
                Spacer()
                Text("\(n)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(Capsule().fill(Tokens.brandBlue))
            }
        } else {
            Label(item.title, systemImage: item.systemImage)
                .badge(n)
        }
    }
}
