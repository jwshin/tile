import AppKit
import Common

/// Owns display layouts, window membership, focus, and restoration validity.
@MainActor final class DisplayLayoutState {
    static var shared = DisplayLayoutState(monitors: monitorInfos)
    private var layouts: [String: Workspace] = [:]
    private var windows: [UInt32: Window] = [:]
    private var mainDisplayId: String?
    private var frozenFocus: FrozenFocus?
    private var lastKnownNativeFocusedWindowId: UInt32?
    private var pendingFocusRecovery = false
    private var screenHistory: [String] = []
    private var focusSequence: UInt64 = 0
    private var restoration: [String: SavedLayout] = [:]

    private struct SavedLayout {
        let layout: BinaryLayout
        let kinds: [UInt32: WindowKind]
        let resumeKinds: [UInt32: WindowKind]
    }

    init(monitors: [MonitorInfo]) { reconcileMonitors(monitors) }
    var workspaces: [Workspace] { layouts.values.sorted() }
    var allWindows: [Window] { windows.values.sorted { $0.windowId < $1.windowId } }
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
        check(window.layoutState === self && windows[window.windowId] == nil)
        windows[window.windowId] = window
    }

    /// All arrivals share one insertion policy, including restoration and screen migration.
    func place(_ window: Window, on requested: Workspace, kind: WindowKind) {
        guard windows[window.windowId] === window else { return }
        check(requested.state === self)
        MouseTiling.shared.cancel()
        let previous = focus
        let destination = contains(requested) ? requested : remainingWorkspace
        let source = window.workspace
        source?.layout.remove(window.windowId)
        if source !== destination { source?.forget(window.windowId) }
        window.workspace = destination
        window.kind = kind == .tiled && !window.isResizable ? .floating : kind
        window.lastAppliedLayoutPhysicalRect = nil
        source?.recover()
        destination.layout.rootAxis = destination.resolvedAxis
        if window.kind == .tiled
            && !destination.layout.insert(
                window.windowId, beside: destination.insertionTarget, placement: config.newWindowPlacement,
                in: destination.layoutRect, gap: CGFloat(config.gap), minimums: destination.minimums
            )
        {
            window.kind = .floating
        }
        if previous.windowOrNil === window {
            setFocus(
                to: window.isFocusable
                    ? LiveFocus(windowOrNil: window, workspace: destination) : destination.toLiveFocus())
            if !window.isFocusable { pendingFocusRecovery = true }
        }
    }

    private var remainingWorkspace: Workspace {
        screenHistory.compactMap { layouts[$0] }.first ?? mainWorkspace
    }

    var focus: LiveFocus {
        guard let frozenFocus else { return mainWorkspace.toLiveFocus() }
        let workspace = workspace(named: frozenFocus.workspaceName)
        if let id = frozenFocus.windowId, let window = windows[id], window.isFocusable,
            window.workspace === workspace
        {
            return LiveFocus(windowOrNil: window, workspace: workspace)
        }
        return workspace.toLiveFocus()
    }
    func importNativeFocus(_ window: Window?) {
        if window?.kind == .popup { return }
        if let window, !window.isFocusable {
            lastKnownNativeFocusedWindowId = nil
            return
        }
        if window?.windowId != lastKnownNativeFocusedWindowId {
            // Cache macOS's automatic replacement without overwriting the recent-focus fallback.
            if !pendingFocusRecovery, let live = window?.toLiveFocusOrNil() { _ = setFocus(to: live) }
            lastKnownNativeFocusedWindowId = window?.windowId
        }
    }

    /// Retain recovery across cancelled refreshes until an execution session can apply native focus.
    func takeFocusRecovery() -> LiveFocus? {
        guard pendingFocusRecovery else { return nil }
        pendingFocusRecovery = false
        return focus
    }

    @discardableResult func setFocus(to newFocus: LiveFocus) -> Bool {
        frozenFocus = newFocus.frozen
        focusSequence += 1
        newFocus.windowOrNil?.lastFocusSequence = focusSequence
        newFocus.windowOrNil?.markRecent()
        screenHistory.removeAll { $0 == newFocus.workspace.name }
        screenHistory.insert(newFocus.workspace.name, at: 0)
        return contains(newFocus.workspace)
    }

    func reconcileMonitors(_ monitors: [MonitorInfo]) {
        guard let main = monitors.first(where: \.isMain) ?? monitors.first else { return }
        let ids = Set(monitors.map(\.displayId))
        let removed = workspaces.filter { !ids.contains($0.name) }
        let geometryChanged = monitors.contains { monitor in
            guard let existing = layouts[monitor.displayId] else { return true }
            return existing.workspaceMonitor.visibleRect.topLeftCorner != monitor.visibleRect.topLeftCorner
                || existing.workspaceMonitor.visibleRect.size != monitor.visibleRect.size
        }
        if !removed.isEmpty || geometryChanged { MouseTiling.shared.cancel() }
        mainDisplayId = main.displayId
        for monitor in monitors { workspace(for: monitor).workspaceMonitor = monitor }
        let destination =
            screenHistory.filter { ids.contains($0) }.compactMap { layouts[$0] }.first ?? workspace(for: main)
        let focusedId = frozenFocus?.windowId
        for source in removed {
            // Capture membership before removing the display; each arrival gets a fresh insertion.
            let incoming =
                source.tiledWindows.map { ($0, $0.kind) }
                + source.windows.filter { $0.kind != .tiled }.map { ($0, $0.kind) }
            source.layout = BinaryLayout()
            layouts.removeValue(forKey: source.name)
            for (window, kind) in incoming { place(window, on: destination, kind: kind) }
        }
        if !removed.isEmpty, let focusedId, let focused = windows[focusedId], let live = focused.toLiveFocusOrNil() {
            setFocus(to: live)
        }
        if !removed.isEmpty { restoration = [:] }
        screenHistory.removeAll { !ids.contains($0) }
        for workspace in workspaces { workspace.recover() }
    }

    func changeLayout<T>(_ body: () async throws -> T) async rethrows -> T {
        restoration = [:]
        defer { restoration = [:] }
        return try await body()
    }

    @discardableResult func removeWindow(_ window: Window, remember: Bool) -> Window? {
        guard windows[window.windowId] === window else { return nil }
        MouseTiling.shared.cancel()
        let previous = focus
        if remember { saveForRestoration() }
        let workspace = window.workspace
        workspace?.layout.remove(window.windowId)
        workspace?.forget(window.windowId)
        windows.removeValue(forKey: window.windowId)
        window.workspace = nil
        workspace?.recover()
        guard let workspace, previous.windowOrNil === window else { return nil }
        let replacement = workspace.toLiveFocus()
        setFocus(to: replacement)
        pendingFocusRecovery = true
        return replacement.windowOrNil
    }

    private func saveForRestoration() {
        let savedIds = Set(restoration.values.flatMap { $0.kinds.keys })
        let currentIds = Set(allWindows.filter { $0.kind != .popup }.map(\.windowId))
        if currentIds.isSubset(of: savedIds) { return }
        restoration = Dictionary(
            uniqueKeysWithValues: workspaces.map { workspace in
                (
                    workspace.name,
                    SavedLayout(
                        layout: workspace.layout,
                        kinds: Dictionary(
                            uniqueKeysWithValues:
                                workspace.windows.filter { $0.kind != .popup }.map { ($0.windowId, $0.kind) }),
                        resumeKinds: Dictionary(
                            uniqueKeysWithValues: workspace.windows.map { ($0.windowId, $0.resumeKind) }))
                )
            })
    }

    @discardableResult func restoreWindow(newlyDetectedWindow window: Window) -> Bool {
        guard restoration.values.contains(where: { $0.kinds[window.windowId] != nil }) else { return false }
        MouseTiling.shared.cancel()
        // Rebuild all saved memberships atomically, without transient insertion failures.
        for (name, saved) in restoration {
            let destination = workspace(named: name)
            for (id, kind) in saved.kinds {
                if let existing = windows[id] {
                    existing.workspace?.layout.remove(id)
                    existing.workspace = destination
                    existing.kind = kind
                    existing.resumeKind = saved.resumeKinds[id] ?? .tiled
                }
            }
        }
        for (name, saved) in restoration {
            let workspace = workspace(named: name)
            let extras = workspace.windows.filter { $0.kind == .tiled && saved.kinds[$0.windowId] == nil }
            workspace.layout = saved.layout
            workspace.layout.retain(Set(workspace.windows.filter { $0.kind == .tiled }.map(\.windowId)))
            workspace.recover()
            for extra in extras {
                if !workspace.layout.insert(
                    extra.windowId, beside: workspace.insertionTarget, placement: config.newWindowPlacement,
                    in: workspace.layoutRect, gap: CGFloat(config.gap), minimums: workspace.minimums)
                {
                    extra.kind = .floating
                }
            }
        }
        return true
    }
}

struct FrozenFocus: Equatable, Sendable {
    let windowId: UInt32?
    let workspaceName: String
}
