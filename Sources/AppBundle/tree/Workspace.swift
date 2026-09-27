import AppKit
import Common

/// A permanent layout for one connected display. Names are internal display IDs.
final class Workspace: TreeNode, NonLeafTreeNodeObject, Hashable, Comparable {
    let name: String
    var workspaceMonitor: MonitorInfo
    unowned let state: DisplayLayoutState

    @MainActor init(monitor: MonitorInfo, state: DisplayLayoutState) {
        name = monitor.displayId
        workspaceMonitor = monitor
        self.state = state
        super.init(parent: NilTreeNode.instance, adaptiveWeight: 0, index: 0)
    }

    @MainActor var isVisible: Bool { state.contains(self) }
    override func getWeight(_ orientation: Orientation) -> CGFloat {
        workspaceMonitor.visibleRectPaddedByOuterGaps.getDimension(orientation)
    }
    override func setWeight(_ orientation: Orientation, _ value: CGFloat) { die("Can't resize a display") }
    nonisolated static func == (lhs: Workspace, rhs: Workspace) -> Bool { lhs === rhs }
    nonisolated static func < (lhs: Workspace, rhs: Workspace) -> Bool { lhs.name < rhs.name }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

extension MonitorInfo {
    @MainActor var activeWorkspace: Workspace { DisplayLayoutState.shared.workspace(for: self) }
}
