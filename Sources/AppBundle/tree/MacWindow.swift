import AppKit
import Common

final class MacWindow: Window {
    let macApp: MacApp
    private var frameRequest: UInt64 = 0

    private init(_ id: UInt32, _ app: MacApp, workspace: Workspace, kind: WindowKind, size: CGSize?) {
        macApp = app
        super.init(id: id, app, workspace: workspace, kind: kind, lastFloatingSize: size)
    }

    static var allWindows: [MacWindow] { DisplayLayoutState.shared.allWindows.compactMap { $0 as? MacWindow } }

    @discardableResult
    static func getOrRegister(windowId: UInt32, macApp: MacApp) async throws -> MacWindow {
        if let existing = Window.get(byId: windowId) as? MacWindow { return existing }
        let destination = focus.workspace
        let rect = try await macApp.getAxRect(windowId, .cancellable)
        var kind = try await classifyWindow(windowId, macApp, .cancellable)
        let resizable = try await macApp.isResizable(windowId, .cancellable)
        if kind == .tiled && !resizable { kind = .floating }
        // AX reads suspend. Resolve identity and display membership again before publishing.
        if let existing = Window.get(byId: windowId) as? MacWindow { return existing }
        let workspace = destination.state.contains(destination) ? destination : focus.workspace
        let window = MacWindow(windowId, macApp, workspace: workspace, kind: kind, size: rect?.size)
        window.isResizable = resizable
        window.layoutState.restoreWindow(newlyDetectedWindow: window)
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
}

extension MacWindow {
    func reclassify(on workspace: Workspace, _ cm: CancellationMode) async throws {
        let kind = try await classifyWindow(windowId, macApp, cm)
        let resizable = try await macApp.isResizable(windowId, cm)
        guard isRegistered, self.kind == .popup else { return }
        isResizable = resizable
        layoutState.place(self, on: workspace, kind: kind)
    }
}

@MainActor private func classifyWindow(_ id: UInt32, _ app: MacApp, _ cm: CancellationMode) async throws -> WindowKind {
    let type = try await app.getAxUiElementWindowType(id, getWindowLevel(for: id), cm)
    return type.initialKind(bundleId: app.rawAppBundleId, floatingApps: config.floatingApps)
}
