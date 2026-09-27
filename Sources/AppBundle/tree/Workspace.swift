import AppKit
import Common

/// A permanent layout for one connected display. Names are internal display IDs.
final class Workspace: TreeNode, NonLeafTreeNodeObject, Hashable, Comparable {
    @MainActor private static var layouts: [String: Workspace] = [:]
    let name: String
    private(set) var workspaceMonitor: MonitorInfo

    @MainActor private init(monitor: MonitorInfo) {
        name = monitor.displayId
        workspaceMonitor = monitor
        super.init(parent: NilTreeNode.instance, adaptiveWeight: 0, index: 0)
    }

    @MainActor static var all: [Workspace] { layouts.values.sorted() }

    @MainActor static func get(byName name: String) -> Workspace {
        // Frozen focus can refer to a disconnected display; resolve it to the main display.
        if let existing = layouts[name] { return existing }
        return mainMonitorInfo.activeWorkspace
    }

    @MainActor static func forMonitor(_ monitor: MonitorInfo) -> Workspace {
        if let existing = layouts[monitor.displayId] { return existing }
        let workspace = Workspace(monitor: monitor)
        layouts[monitor.displayId] = workspace
        return workspace
    }

    /// Reconcile by display identity, not coordinates: moving a display must not exchange layouts.
    @MainActor static func reconcileMonitors(_ monitors: [MonitorInfo]) {
        // macOS can temporarily report no displays during reconfiguration or sleep.
        guard let main = monitors.first(where: \.isMain) ?? monitors.first else { return }
        let ids = Set(monitors.map(\.displayId))
        let removed = all.filter { !ids.contains($0.name) }
        for monitor in monitors { forMonitor(monitor).workspaceMonitor = monitor }
        let destination = forMonitor(main)
        for source in removed {
            // Preserve the detached display's tiling subtree, including order and sizing.
            let incoming = source.rootTilingContainer
            if !incoming.children.isEmpty {
                let current = destination.rootTilingContainer
                if current.children.isEmpty {
                    current.unbindFromParent()
                    incoming.bind(to: destination, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
                } else if current.orientation == incoming.orientation {
                    // Group both trees under the opposite orientation so normalization
                    // preserves each display's internal arrangement.
                    current.unbindFromParent()
                    let group = TilingContainer(
                        parent: destination, adaptiveWeight: 1,
                        current.orientation.opposite, index: INDEX_BIND_LAST)
                    current.bind(to: group, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
                    incoming.bind(to: group, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
                } else {
                    incoming.bind(to: current, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
                }
            }
            for window in source.floatingWindows {
                window.bindAsFloatingWindow(to: destination)
            }
            for window in source.macOsNativeFullscreenWindowsContainer.children {
                window.bind(
                    to: destination.macOsNativeFullscreenWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER,
                    index: INDEX_BIND_LAST)
            }
            for window in source.macOsNativeHiddenAppsWindowsContainer.children {
                window.bind(
                    to: destination.macOsNativeHiddenAppsWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER,
                    index: INDEX_BIND_LAST)
            }
            layouts.removeValue(forKey: source.name)
        }
        if !removed.isEmpty { resetClosedWindowsCache() }
    }

    @MainActor static func garbageCollectUnusedWorkspaces() { reconcileMonitors(monitorInfos) }

    @MainActor var isVisible: Bool { Self.layouts[name] === self }

    override func getWeight(_ orientation: Orientation) -> CGFloat {
        workspaceMonitor.visibleRectPaddedByOuterGaps.getDimension(orientation)
    }
    override func setWeight(_ orientation: Orientation, _ value: CGFloat) { die("Can't resize a display") }
    nonisolated static func == (lhs: Workspace, rhs: Workspace) -> Bool { lhs === rhs }
    nonisolated static func < (lhs: Workspace, rhs: Workspace) -> Bool { lhs.name < rhs.name }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

extension MonitorInfo {
    @MainActor var activeWorkspace: Workspace { Workspace.forMonitor(self) }
}

@MainActor func gcMonitors() { Workspace.reconcileMonitors(monitorInfos) }
