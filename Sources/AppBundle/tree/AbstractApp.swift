import Common

protocol AbstractApp: AnyObject, Hashable, TileValue {
    var pid: Int32 { get }

    @MainActor func getFocusedWindow(_ cm: CancellationMode) async throws -> Window?
    var name: String? { get }
    @MainActor var isHidden: Bool { get }
}

extension AbstractApp {
    static func == (lhs: Self, rhs: Self) -> Bool {
        if lhs.pid == rhs.pid {
            check(lhs === rhs)
            return true
        } else {
            check(lhs !== rhs)
            return false
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
    }
}
