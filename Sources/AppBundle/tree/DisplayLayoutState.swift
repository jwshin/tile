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

    /// All membership changes remove the old leaf before inserting at the destination.
    func place(
        _ window: Window, on requested: Workspace, kind: WindowKind, beside target: UInt32? = nil,
        direction: CardinalDirection? = nil
    ) {
        guard windows[window.windowId] === window else { return }
        check(requested.state === self)
        let destination = contains(requested) ? requested : mainWorkspace
        let selected = focus.windowOrNil
        let focusedTarget =
            selected?.workspace === destination && selected?.kind == .tiled
                && selected !== window ? selected?.windowId : nil
        if let source = window.workspace {
            source.layout.remove(window.windowId)
            source.forget(window.windowId)
        }
        window.workspace = destination
        window.kind = kind
        window.lastAppliedLayoutPhysicalRect = nil
        if kind == .tiled {
            destination.layout.insert(
                window.windowId, beside: target ?? focusedTarget ?? destination.insertionTarget,
                direction: direction, in: destination.layoutRect, gap: CGFloat(config.gap))
        }
        if window.isFocusable { destination.markRecent(window.windowId) }
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
        if window?.windowId != lastKnownNativeFocusedWindowId {
            if let live = window?.toLiveFocusOrNil() { _ = setFocus(to: live) }
            lastKnownNativeFocusedWindowId = window?.windowId
        }
    }
    @discardableResult func setFocus(to newFocus: LiveFocus) -> Bool {
        frozenFocus = newFocus.frozen
        newFocus.windowOrNil?.markRecent()
        return contains(newFocus.workspace)
    }

    func reconcileMonitors(_ monitors: [MonitorInfo]) {
        guard let main = monitors.first(where: \.isMain) ?? monitors.first else { return }
        mainDisplayId = main.displayId
        let ids = Set(monitors.map(\.displayId))
        let removed = workspaces.filter { !ids.contains($0.name) }
        for monitor in monitors { workspace(for: monitor).workspaceMonitor = monitor }
        let destination = workspace(for: main)
        for source in removed {
            destination.layout.merge(
                source.layout, axis: destination.layoutRect.width >= destination.layoutRect.height ? .h : .v)
            for window in source.windows {
                window.workspace = destination
                if window.isFocusable { destination.markRecent(window.windowId) }
            }
            if frozenFocus?.workspaceName == source.name {
                frozenFocus = FrozenFocus(windowId: frozenFocus?.windowId, workspaceName: destination.name)
            }
            source.layout = BinaryLayout()
            layouts.removeValue(forKey: source.name)
        }
        if !removed.isEmpty { restoration = [:] }
    }

    func changeLayout<T>(_ body: () async throws -> T) async rethrows -> T {
        restoration = [:]
        defer { restoration = [:] }
        return try await body()
    }

    @discardableResult func removeWindow(_ window: Window, remember: Bool) -> Window? {
        guard windows[window.windowId] === window else { return nil }
        let previous = focus
        if remember { saveForRestoration() }
        let workspace = window.workspace
        workspace?.layout.remove(window.windowId)
        workspace?.forget(window.windowId)
        windows.removeValue(forKey: window.windowId)
        window.workspace = nil
        guard let workspace, previous.windowOrNil === window else { return nil }
        let replacement = workspace.toLiveFocus()
        setFocus(to: replacement)
        return replacement.windowOrNil?.app.pid != window.app.pid ? replacement.windowOrNil : nil
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
        // Restore membership first; then rebuild from value snapshots, pruning absent leaves.
        for (name, saved) in restoration {
            let destination = workspace(named: name)
            for (id, kind) in saved.kinds {
                if let window = windows[id] {
                    place(window, on: destination, kind: kind)
                    window.resumeKind = saved.resumeKinds[id] ?? .tiled
                }
            }
        }
        for (name, saved) in restoration {
            let workspace = workspace(named: name)
            let extraIds = workspace.layout.windowIds.filter { saved.kinds[$0] == nil }
            var restored = saved.layout
            restored.retain(Set(workspace.windows.filter { $0.kind == .tiled }.map(\.windowId)))
            for id in extraIds {
                restored.insert(id, beside: restored.windowIds.last, in: workspace.layoutRect, gap: CGFloat(config.gap))
            }
            workspace.layout = restored
        }
        return true
    }
}

struct FrozenFocus: Equatable, Sendable {
    let windowId: UInt32?
    let workspaceName: String
}
