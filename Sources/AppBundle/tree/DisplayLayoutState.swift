import AppKit
import Common

/// Owns display layouts, window identity, focus, and restoration validity.
@MainActor final class DisplayLayoutState {
    static var shared = DisplayLayoutState(monitors: monitorInfos)

    private var layouts: [String: Workspace] = [:]
    private var windows: [UInt32: Window] = [:]
    private var mainDisplayId: String?
    private var frozenFocus: FrozenFocus?
    private var lastKnownNativeFocusedWindowId: UInt32?
    private var closedWindowsCache = FrozenWorld(workspaces: [], windowIds: [])
    lazy var minimizedWindows = MacosMinimizedWindowsContainer(state: self)
    lazy var popupWindows = MacosPopupWindowsContainer(state: self)

    init(monitors: [MonitorInfo]) { reconcileMonitors(monitors) }

    var workspaces: [Workspace] { layouts.values.sorted() }
    var allWindows: [Window] { Array(windows.values) }
    var mainWorkspace: Workspace {
        if let mainDisplayId, let workspace = layouts[mainDisplayId] { return workspace }
        return workspace(for: mainMonitorInfo)
    }

    func workspace(for monitor: MonitorInfo) -> Workspace {
        if let existing = layouts[monitor.displayId] { return existing }
        let workspace = Workspace(monitor: monitor, state: self)
        layouts[monitor.displayId] = workspace
        return workspace
    }

    func workspace(named name: String) -> Workspace { layouts[name] ?? mainWorkspace }
    func contains(_ workspace: Workspace) -> Bool { layouts[workspace.name] === workspace }
    func window(for id: UInt32) -> Window? { windows[id] }
    func register(_ window: Window) {
        check(window.layoutState === self)
        check(windows[window.windowId] == nil)
        windows[window.windowId] = window
    }

    var focus: LiveFocus {
        guard let frozenFocus else { return mainWorkspace.toLiveFocus() }
        let workspaceFocus = workspace(named: frozenFocus.workspaceName).toLiveFocus()
        let windowFocus = frozenFocus.windowId.flatMap { window(for: $0) }?.toLiveFocusOrNil() ?? workspaceFocus
        return workspaceFocus.workspace != windowFocus.workspace ? workspaceFocus : windowFocus
    }

    func importNativeFocus(_ window: Window?) {
        if window?.parent is MacosPopupWindowsContainer { return }
        if window?.windowId != lastKnownNativeFocusedWindowId {
            if let live = window?.toLiveFocusOrNil() { _ = setFocus(to: live) }
            lastKnownNativeFocusedWindowId = window?.windowId
        }
    }

    @discardableResult
    func setFocus(to newFocus: LiveFocus) -> Bool {
        if frozenFocus == newFocus.frozen { return true }
        let oldFocus = focus
        // Normalize mruWindow when focus away from a workspace
        if oldFocus.workspace != newFocus.workspace {
            oldFocus.windowOrNil?.markAsMostRecentChild()
        }

        frozenFocus = newFocus.frozen
        let status = newFocus.workspace.isVisible

        newFocus.windowOrNil?.markAsMostRecentChild()
        return status
    }
    /// Reconcile by display identity, not coordinates: moving a display must not exchange layouts.
    func reconcileMonitors(_ monitors: [MonitorInfo]) {
        // macOS can temporarily report no displays during reconfiguration or sleep.
        guard let main = monitors.first(where: \.isMain) ?? monitors.first else { return }
        mainDisplayId = main.displayId
        let ids = Set(monitors.map(\.displayId))
        let removed = workspaces.filter { !ids.contains($0.name) }
        for monitor in monitors { workspace(for: monitor).workspaceMonitor = monitor }
        let destination = workspace(for: main)
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
        if !removed.isEmpty { invalidateRestoration() }
    }

    func normalize() {
        for workspace in workspaces { workspace.normalizeContainers() }
    }

    /// Layout edits invalidate restoration even if an edit reports failure.
    func changeLayout<T>(_ body: () async throws -> T) async rethrows -> T {
        invalidateRestoration()
        defer { invalidateRestoration() }
        return try await body()
    }

    /// Returns a replacement focus only when macOS must be nudged to another app.
    @discardableResult
    func removeWindow(_ window: Window, remember: Bool) -> Window? {
        guard windows[window.windowId] === window else { return nil }
        if remember { cacheClosedWindowIfNeeded() }
        windows.removeValue(forKey: window.windowId)
        let parent = window.unbindFromParent().parent
        let oldFocus = focus
        guard let workspace = parent.nodeWorkspace, workspace == oldFocus.workspace else { return nil }
        switch parent.cases {
        case .tilingContainer, .floatingWindowsContainer, .macosHiddenAppsWindowsContainer,
            .macosFullscreenWindowsContainer:
            let replacement = workspace.toLiveFocus()
            _ = setFocus(to: replacement)
            return oldFocus.windowOrNil?.app.pid != window.app.pid ? replacement.windowOrNil : nil
        default: return nil
        }
    }

    private func invalidateRestoration() {
        closedWindowsCache = FrozenWorld(workspaces: [], windowIds: [])
    }

    private func cacheClosedWindowIfNeeded() {
        let allWs = workspaces
        let allWindowIds = allWs.flatMap { collectAllWindowIdsRecursive($0) }.toSet()
        if allWindowIds.isSubset(of: closedWindowsCache.windowIds) {
            return  // already cached
        }
        closedWindowsCache = FrozenWorld(
            workspaces: allWs.map { FrozenWorkspace($0) },
            windowIds: allWindowIds,
        )
    }

    @discardableResult
    func restoreWindow(newlyDetectedWindow: Window) async throws -> Bool {
        if !closedWindowsCache.windowIds.contains(newlyDetectedWindow.windowId) {
            return false
        }

        for frozenWorkspace in closedWindowsCache.workspaces {
            let workspace = workspace(named: frozenWorkspace.name)
            for frozenWindow in frozenWorkspace.floatingWindows {
                window(for: frozenWindow.id)?.bindAsFloatingWindow(to: workspace)
            }
            for frozenWindow in frozenWorkspace.macosUnconventionalWindows {  // Will get fixed by normalizations
                window(for: frozenWindow.id)?.bindAsFloatingWindow(to: workspace)
            }
            let prevRoot = workspace.rootTilingContainer  // Save prevRoot into a variable to avoid it being garbage collected earlier than needed
            let potentialOrphans = prevRoot.allLeafWindowsRecursive
            prevRoot.unbindFromParent()
            restoreTreeRecursive(
                frozenContainer: frozenWorkspace.rootTilingNode, parent: workspace, index: INDEX_BIND_LAST)
            for window in (potentialOrphans - workspace.rootTilingContainer.allLeafWindowsRecursive) {
                try await window.relayoutWindow(on: workspace, .cancellable, forceTile: true)
            }
        }

        return true
    }

    @discardableResult
    private func restoreTreeRecursive(frozenContainer: FrozenContainer, parent: NonLeafTreeNodeObject, index: Int)
        -> Bool
    {
        let container = TilingContainer(
            parent: parent,
            adaptiveWeight: frozenContainer.weight,
            frozenContainer.orientation,
            index: index,
        )

        for (index, child) in frozenContainer.children.enumerated() {
            switch child {
            case .window(let w):
                // Stop the loop if can't find the window, because otherwise all the subsequent windows will have incorrect index
                guard let window = window(for: w.id) else { return false }
                window.bind(to: container, adaptiveWeight: w.weight, index: index)
            case .container(let c):
                // There is no reason to continue
                if !restoreTreeRecursive(frozenContainer: c, parent: container, index: index) { return false }
            }
        }
        return true
    }

}

struct FrozenFocus: TileValue, Equatable, Sendable {
    let windowId: UInt32?
    let workspaceName: String
}
