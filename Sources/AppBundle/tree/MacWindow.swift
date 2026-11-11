import AppKit
import Common

final class MacWindow: Window {
    let macApp: MacApp
    private var frameRequest: UInt64 = 0
    private let listedFloatingAtDiscovery: Bool

    private init(
        _ id: UInt32, _ app: MacApp, workspace: Workspace, kind: WindowKind, size: CGSize?,
        listedFloatingAtDiscovery: Bool
    ) {
        macApp = app
        self.listedFloatingAtDiscovery = listedFloatingAtDiscovery
        super.init(id: id, app, workspace: workspace, kind: kind, lastFloatingSize: size)
    }

    static var allWindows: [MacWindow] { DisplayLayoutState.shared.allWindows.compactMap { $0 as? MacWindow } }

    @discardableResult
    static func getOrRegister(windowId: UInt32, macApp: MacApp) async throws -> MacWindow {
        let state = DisplayLayoutState.shared
        let generation = state.lifecycleGeneration
        try state.checkLifecycle(generation)
        if let existing = Window.get(byId: windowId) as? MacWindow { return existing }
        let destination = focus.workspace
        let listedFloating = macApp.rawAppBundleId.map(config.floatingApps.contains) == true
        let rect = try await macApp.getAxRect(windowId, .cancellable)
        try state.checkLifecycle(generation)
        let fullscreen = try await macApp.isMacosNativeFullscreen(windowId, .cancellable) == true
        try state.checkLifecycle(generation)
        let minimized = fullscreen ? false : (try await macApp.isMacosNativeMinimized(windowId, .cancellable) == true)
        try state.checkLifecycle(generation)
        let deferredNativeKind: WindowKind? =
            fullscreen ? .nativeFullscreen : minimized ? .minimized : macApp.isHidden ? .hidden : nil
        let kind: WindowKind
        let resizable: Bool
        if let deferredNativeKind {
            // Minimized, hidden, and fullscreen windows expose AXDialog subroles or nil window levels;
            // defer window-kind classification until the window becomes available on screen.
            kind = deferredNativeKind
            resizable = true
        } else {
            var classified = try await classifyWindow(
                windowId, macApp, .cancellable, listedFloating: listedFloating)
            try state.checkLifecycle(generation)
            resizable = try await macApp.isResizable(windowId, .cancellable)
            try state.checkLifecycle(generation)
            if classified == .tiled && !resizable { classified = .floating }
            kind = classified
        }
        // AX reads suspend. Resolve identity and display membership again before publishing.
        if let existing = Window.get(byId: windowId) as? MacWindow { return existing }
        let workspace = destination.state.contains(destination) ? destination : focus.workspace
        let window = MacWindow(
            windowId, macApp, workspace: workspace, kind: kind, size: rect?.size,
            listedFloatingAtDiscovery: listedFloating)
        window.isResizable = resizable
        window.needsClassificationOnResume = deferredNativeKind != nil
        if window.layoutState.restoreWindow(newlyDetectedWindow: window) {
            window.needsClassificationOnResume = false
        }
        return window
    }

    // todo cache
    func isWindowHeuristic(_ windowLevel: MacOsWindowLevel?, _ cm: CancellationMode) async throws -> Bool {
        try await macApp.isWindowHeuristic(windowId, windowLevel, cm)
    }

    // skipClosedWindowsCache is an optimization when it's definitely not necessary to cache closed window.
    //                        If you are unsure, it's better to pass `false`
    @MainActor
    func garbageCollect(skipClosedWindowsCache: Bool) {
        layoutState.removeWindow(self, remember: !skipClosedWindowsCache)
    }

    override func isMacosFullscreen(_ cm: CancellationMode) async throws -> Bool? {
        try await macApp.isMacosNativeFullscreen(windowId, cm)
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
        guard !layoutState.isRecoveringDisplays else { return }
        frameRequest += 1
        let request = frameRequest
        macApp.setAxFrame(windowId, topLeft, size) { [weak self] actual in
            guard let self, self.frameRequest == request, let size else { return }
            if self.observeAppliedSize(requested: size, actual: actual) {
                ActionExecution.shared.scheduleRefresh(.ax("ObservedWindowMinimum"))
            }
        }
    }

    override func getAxRect(_ cm: CancellationMode) async throws -> Rect? {
        try await macApp.getAxRect(windowId, cm)
    }

    override func cancelPendingFrame() {
        frameRequest += 1
        macApp.cancelPendingFrame(windowId)
    }

    override func classifyOnResume() async throws -> (kind: WindowKind, isResizable: Bool)? {
        let generation = layoutState.lifecycleGeneration
        try layoutState.checkLifecycle(generation)
        invalidateWindowLevelCache()
        let kind = try await classifyWindow(
            windowId, macApp, .cancellable, listedFloating: listedFloatingAtDiscovery)
        try layoutState.checkLifecycle(generation)
        let resizable = try await macApp.isResizable(windowId, .cancellable)
        try layoutState.checkLifecycle(generation)
        return (kind, resizable)
    }
}

extension MacWindow {
    @discardableResult
    func reclassify(on workspace: Workspace, _ cm: CancellationMode) async throws -> Bool {
        let generation = layoutState.lifecycleGeneration
        try layoutState.checkLifecycle(generation)
        let kind = try await classifyWindow(
            windowId, macApp, cm,
            listedFloating: macApp.rawAppBundleId.map(config.floatingApps.contains) == true)
        try layoutState.checkLifecycle(generation)
        let resizable = try await macApp.isResizable(windowId, cm)
        try layoutState.checkLifecycle(generation)
        guard isRegistered, self.kind == .popup else { return false }
        isResizable = resizable
        layoutState.place(self, on: workspace, kind: kind)
        return self.kind != .popup
    }
}

@MainActor private func classifyWindow(
    _ id: UInt32, _ app: MacApp, _ cm: CancellationMode, listedFloating: Bool
) async throws -> WindowKind {
    let type = try await app.getAxUiElementWindowType(id, getWindowLevel(for: id), cm)
    if type == .popup { return .popup }
    if listedFloating { return .floating }
    return type == .dialog ? .floating : .tiled
}
