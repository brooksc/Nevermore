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
            ForEach(Collection.Section.allCases) { section in
                // Hide the ATTENTION section entirely when nothing reappeared.
                if section != .attention || model.count(for: .reappeared) > 0 {
                    Section(section.rawValue) {
                        ForEach(section.members) { item in
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
    private func row(_ item: Collection) -> some View {
        let n = model.count(for: item)
        if item == .reappeared {
            // Reappeared uses an accent pill, not a plain count (design 1a).
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
