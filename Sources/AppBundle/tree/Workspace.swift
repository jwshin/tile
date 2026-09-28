import AppKit
import Common

/// One permanent display layout. Native windows are registered separately from the value tree.
@MainActor final class Workspace: Hashable, Comparable {
    nonisolated let name: String
    var workspaceMonitor: MonitorInfo
    unowned let state: DisplayLayoutState
    var layout = BinaryLayout()
    var orientationOverride: Orientation?
    private var recentWindowIds: [UInt32] = []

    init(monitor: MonitorInfo, state: DisplayLayoutState) {
        name = monitor.displayId
        workspaceMonitor = monitor
        self.state = state
        layout.rootAxis = resolvedAxis
    }

    var isVisible: Bool { state.contains(self) }
    var windows: [Window] { state.allWindows.filter { $0.workspace === self } }
    var tiledWindows: [Window] { layout.windowIds.compactMap { state.window(for: $0) } }
    var floatingWindows: [Window] { windows.filter { $0.kind == .floating } }
    var isEffectivelyEmpty: Bool { windows.allSatisfy { !$0.isFocusable } }
    var mostRecentWindow: Window? {
        recentWindowIds.compactMap { state.window(for: $0) }.first { $0.workspace === self && $0.isFocusable }
            ?? windows.last { $0.isFocusable }
    }
    var insertionTarget: UInt32? {
        recentWindowIds.first { layout.windowIds.contains($0) } ?? layout.windowIds.last
    }
    var layoutRect: Rect {
        var rect = workspaceMonitor.visibleRectPaddedByOuterGaps
        // macOS can reject a full-height frame for some multi-display arrangements.
        rect.height = max(0, rect.height - 1)
        return rect
    }
    var resolvedAxis: Orientation {
        orientationOverride ?? config.rootOrientation.axis ?? (layoutRect.width >= layoutRect.height ? .h : .v)
    }
    var minimums: BinaryLayout.Minimums {
        Dictionary(uniqueKeysWithValues: windows.map { ($0.windowId, $0.minimumSize) })
    }
    func recover() {
        layout.rootAxis = resolvedAxis
        let oldest = tiledWindows.sorted {
            $0.lastFocusSequence == $1.lastFocusSequence
                ? $0.windowId < $1.windowId : $0.lastFocusSequence < $1.lastFocusSequence
        }.map(\.windowId)
        for id in layout.recover(in: layoutRect, gap: CGFloat(config.gap), minimums: minimums, oldestFirst: oldest) {
            state.window(for: id)?.kind = .floating
        }
    }
    func flipOrientation() {
        orientationOverride = resolvedAxis.opposite
        recover()
    }
    var tiledFrames: [UInt32: Rect] { layout.frames(in: layoutRect, gap: CGFloat(config.gap)) }

    func markRecent(_ id: UInt32) {
        recentWindowIds.removeAll { $0 == id }
        recentWindowIds.insert(id, at: 0)
    }
    func forget(_ id: UInt32) { recentWindowIds.removeAll { $0 == id } }

    nonisolated static func == (lhs: Workspace, rhs: Workspace) -> Bool { lhs === rhs }
    nonisolated static func < (lhs: Workspace, rhs: Workspace) -> Bool { lhs.name < rhs.name }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

extension MonitorInfo {
    @MainActor var activeWorkspace: Workspace { DisplayLayoutState.shared.workspace(for: self) }
}
