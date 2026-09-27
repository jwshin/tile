import AppKit
import Common

final class MacWindow: Window {
    let macApp: MacApp

    @MainActor
    private init(
        _ id: UInt32, _ actor: MacApp, lastFloatingSize: CGSize?, parent: NonLeafTreeNodeObject,
        adaptiveWeight: CGFloat, index: Int
    ) {
        self.macApp = actor
        super.init(
            id: id, actor, lastFloatingSize: lastFloatingSize, parent: parent, adaptiveWeight: adaptiveWeight,
            index: index)
    }

    @MainActor static var allWindowsMap: [UInt32: MacWindow] = [:]
    @MainActor static var allWindows: [MacWindow] { Array(allWindowsMap.values) }

    @MainActor
    @discardableResult
    static func getOrRegister(windowId: UInt32, macApp: MacApp) async throws -> MacWindow {
        if let existing = allWindowsMap[windowId] { return existing }
        let rect = try await macApp.getAxRect(windowId, .cancellable)
        let data = try await unbindAndGetBindingDataForNewWindow(
            windowId,
            macApp,
            (rect?.center.monitorApproximation ?? focus.workspace.workspaceMonitor).activeWorkspace,
            window: nil,
            .cancellable,
        )

        // atomic synchronous section
        if let existing = allWindowsMap[windowId] { return existing }
        let window = MacWindow(
            windowId, macApp, lastFloatingSize: rect?.size, parent: data.parent, adaptiveWeight: data.adaptiveWeight,
            index: data.index)
        allWindowsMap[windowId] = window

        _ = try await restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: window)
        return window
    }

    func isWindowHeuristic(_ windowLevel: MacOsWindowLevel?, _ cm: CancellationMode) async throws -> Bool {  // todo cache
        try await macApp.isWindowHeuristic(windowId, windowLevel, cm)
    }

    // skipClosedWindowsCache is an optimization when it's definitely not necessary to cache closed window.
    //                        If you are unsure, it's better to pass `false`
    @MainActor
    func garbageCollect(skipClosedWindowsCache: Bool) {
        if MacWindow.allWindowsMap.removeValue(forKey: windowId) == nil {
            return
        }
        if !skipClosedWindowsCache { cacheClosedWindowIfNeeded() }
        let parent = unbindFromParent().parent
        let deadWindowWorkspace = parent.nodeWorkspace
        let focus = focus
        if let deadWindowWorkspace, deadWindowWorkspace == focus.workspace {
            switch parent.cases {
            case .tilingContainer, .floatingWindowsContainer, .macosHiddenAppsWindowsContainer,
                .macosFullscreenWindowsContainer:
                let deadWindowFocus = deadWindowWorkspace.toLiveFocus()
                _ = setFocus(to: deadWindowFocus)
                // Guard against "Apple Reminders popup" bug: https://github.com/nikitabobko/AeroSpace/issues/201
                if focus.windowOrNil?.app.pid != app.pid {
                    // Force focus to fix macOS annoyance with focused apps without windows.
                    //   https://github.com/nikitabobko/AeroSpace/issues/65
                    deadWindowFocus.windowOrNil?.nativeFocus()
                }
            case .macosPopupWindowsContainer,  // Don't switch back on popup destruction
                .workspace,  // Workspace is invalid parent for windows
                .macosMinimizedWindowsContainer:  // Don't switch back on minimized windows destruction
                break
            }
        }
    }

    override func isMacosFullscreen(_ cm: CancellationMode) async throws -> Bool {
        try await macApp.isMacosNativeFullscreen(windowId, cm) == true
    }
    override func isMacosMinimized(_ cm: CancellationMode) async throws -> Bool {
        try await macApp.isMacosNativeMinimized(windowId, cm) == true
    }

    @MainActor override func nativeFocus() {
        macApp.nativeFocus(windowId)
    }

    override func closeAxWindow() {
        garbageCollect(skipClosedWindowsCache: true)
        macApp.closeAndUnregisterAxWindow(windowId)
    }

    override func getAxSize(_ cm: CancellationMode) async throws -> CGSize? {
        try await macApp.getAxSize(windowId, cm)
    }

    override func setAxFrame(_ topLeft: CGPoint?, _ size: CGSize?) {
        macApp.setAxFrame(windowId, topLeft, size)
    }

    override func getAxRect(_ cm: CancellationMode) async throws -> Rect? {
        try await macApp.getAxRect(windowId, cm)
    }
}

extension Window {
    @MainActor
    func relayoutWindow(on workspace: Workspace, _ cm: CancellationMode, forceTile: Bool = false) async throws {
        let data =
            forceTile
            ? unbindAndGetBindingDataForNewTilingWindow(workspace, window: self)
            : try await unbindAndGetBindingDataForNewWindow(
                self.asMacWindow().windowId, self.asMacWindow().macApp, workspace, window: self, cm)
        bind(to: data.parent, adaptiveWeight: data.adaptiveWeight, index: data.index)
    }
}

// The function is private because it's unsafe. It leaves the window in unbound state
@MainActor
private func unbindAndGetBindingDataForNewWindow(
    _ windowId: UInt32, _ macApp: MacApp, _ workspace: Workspace, window: Window?, _ cm: CancellationMode
) async throws -> BindingData {
    let windowLevel = getWindowLevel(for: windowId)
    let type = try await macApp.getAxUiElementWindowType(windowId, windowLevel, cm)
    if type != .popup, config.floatingApps.contains(macApp.rawAppBundleId ?? "") {
        return BindingData(
            parent: workspace.floatingWindowsContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    }
    return switch type {
    case .popup: BindingData(parent: macosPopupWindowsContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    case .dialog:
        BindingData(parent: workspace.floatingWindowsContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    case .window: unbindAndGetBindingDataForNewTilingWindow(workspace, window: window)
    }
}

// The function is private because it's unsafe. It leaves the window in unbound state
@MainActor
private func unbindAndGetBindingDataForNewTilingWindow(_ workspace: Workspace, window: Window?) -> BindingData {
    window?.unbindFromParent()  // It's important to unbind to get correct data from below
    let mruWindow = workspace.mostRecentWindowRecursive
    if let mruWindow, let tilingParent = mruWindow.parent as? TilingContainer {
        return BindingData(
            parent: tilingParent,
            adaptiveWeight: WEIGHT_AUTO,
            index: mruWindow.ownIndex.orDie() + 1,
        )
    } else {
        return BindingData(
            parent: workspace.rootTilingContainer,
            adaptiveWeight: WEIGHT_AUTO,
            index: INDEX_BIND_LAST,
        )
    }
}
