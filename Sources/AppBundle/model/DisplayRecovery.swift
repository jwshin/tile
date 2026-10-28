import Foundation

/// In-memory protection for system/display sleep. Times are monotonic seconds and injectable in tests.
@MainActor struct DisplayRecovery {
    enum Reason: Hashable { case system, screens }
    static let settlingTime: TimeInterval = 1
    static let missingDisplayGrace: TimeInterval = 10
    private var reasons: Set<Reason> = []
    private var expected: [Geometry] = []
    private var wakeTime: TimeInterval?
    private var candidate: [Geometry] = []
    private var candidateSince: TimeInterval = 0
    private(set) var isProtected = false

    private struct Geometry: Equatable {
        let id: String
        let x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat
        let isMain: Bool
        init(_ monitor: MonitorInfo) {
            id = monitor.displayId
            let rect = monitor.visibleRect
            x = rect.minX
            y = rect.minY
            width = rect.width
            height = rect.height
            isMain = monitor.isMain
        }
    }

    mutating func sleep(_ reason: Reason, monitors: [MonitorInfo]) {
        if !isProtected { expected = monitors.map(Geometry.init) }
        isProtected = true
        reasons.insert(reason)
        wakeTime = nil
        candidate = []
    }

    mutating func wake(_ reason: Reason, at now: TimeInterval) {
        reasons.remove(reason)
        guard isProtected, reasons.isEmpty, wakeTime == nil else { return }
        wakeTime = now
        candidate = []
        candidateSince = now
    }

    /// Returns true exactly when recovery ends. No layout is mutated while sampling topology.
    mutating func advance(_ monitors: [MonitorInfo], at now: TimeInterval) -> Bool {
        guard isProtected, reasons.isEmpty, let wakeTime else { return false }
        let geometry = monitors.map(Geometry.init).sorted { $0.id < $1.id }
        if candidate != geometry {
            candidate = geometry
            candidateSince = now
        }
        guard !geometry.isEmpty, geometry.allSatisfy({ $0.width > 0 && $0.height > 0 }),
            now - candidateSince >= Self.settlingTime,
            expected.allSatisfy({ geometry.contains($0) }) || now - wakeTime >= Self.missingDisplayGrace
        else { return false }
        isProtected = false
        self.wakeTime = nil
        return true
    }

    func shouldPoll(at now: TimeInterval) -> Bool {
        guard isProtected, reasons.isEmpty, let wakeTime else { return false }
        // After the grace period, no usable screens means wait for the next display event.
        return now - wakeTime < Self.missingDisplayGrace
            || (!candidate.isEmpty && candidate.allSatisfy { $0.width > 0 && $0.height > 0 })
    }
}
