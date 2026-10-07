import Foundation

/// Bounded, in-memory evidence of reconciliation and foreground sessions.
@MainActor final class SessionDiagnostics {
    private struct Pending {
        let description: String
        let started: Date
        let windowIds: Set<UInt32>
    }
    private var pending: [UUID: Pending] = [:]
    private(set) var recent: [String] = []

    func begin(_ description: String, windowIds: [UInt32]) -> UUID {
        let id = UUID()
        pending[id] = Pending(description: description, started: Date(), windowIds: Set(windowIds))
        return id
    }

    func finish(_ id: UUID, outcome: String, windowIds: [UInt32]) {
        guard let session = pending.removeValue(forKey: id) else { return }
        let current = Set(windowIds)
        let added = current.subtracting(session.windowIds).sorted()
        let removed = session.windowIds.subtracting(current).sorted()
        recent.append(
            "\(session.started.ISO8601Format()) \(session.description): \(outcome); "
                + "\(windowIds.count) windows; added=\(added) removed=\(removed)")
        recent = Array(recent.suffix(50))
    }

    var report: String {
        let active = pending.values.sorted { $0.started < $1.started }.map {
            "\($0.started.ISO8601Format()) \($0.description): in progress"
        }
        return
            (["Sessions in progress:"] + (active.isEmpty ? ["none"] : active)
            + ["Recent sessions (oldest first, last 50):"] + (recent.isEmpty ? ["none"] : recent))
            .joined(separator: "\n")
    }
}
