import Foundation
import NevermoreKit

/// A flattened, display-ready view of a ``SenderGroup`` for the table.
struct SenderRow: Identifiable, Hashable {
    let id: GroupID
    let name: String
    let email: String
    let latestSubject: String
    let count: Int
    let unreadPercent: Int
    let lastReceived: Date
    let method: UnsubscribeMethod
    /// Outcome of a prior unsubscribe, if any.
    let priorOutcome: MessageStore.Outcome?
    /// What this sender's stored messages occupy on the server.
    let storage: SenderStorage

    /// Sort key for the Size column. See `SenderStorage.sortKey`.
    var storageBytes: Int { storage.sortKey }

    init(group: SenderGroup, priorOutcome: MessageStore.Outcome?) {
        self.id = group.id
        self.name = group.displayName
        self.email = group.latest?.sender.address ?? group.id.key
        self.latestSubject = group.latest?.subject ?? ""
        self.count = group.total
        self.unreadPercent = Int(group.unreadPercent.rounded())
        self.lastReceived = group.newest
        self.method = Self.method(for: group)
        self.priorOutcome = priorOutcome
        self.storage = group.storage
    }

    static func method(for group: SenderGroup) -> UnsubscribeMethod {
        guard let unsub = group.unsubscribeSource?.unsubscribe else { return .manual }
        if unsub.supportsOneClick { return .oneClick }
        if !unsub.webTargets.isEmpty { return .webLink }
        if !unsub.mailtoTargets.isEmpty { return .email }
        return .manual
    }

    /// Relative age, matching the design's "2h ago" / "3d ago" / "Mar 4".
    var relativeAge: String {
        let seconds = Date().timeIntervalSince(lastReceived)
        if seconds < 3600 { return "\(max(1, Int(seconds / 60)))m ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h ago" }
        if seconds < 7 * 86_400 { return "\(Int(seconds / 86_400))d ago" }
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDate(lastReceived, equalTo: Date(), toGranularity: .year)
            ? "MMM d" : "MMM d, yyyy"
        return formatter.string(from: lastReceived)
    }
}
