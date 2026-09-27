import AppKit
import Common

final class MacWindow: Window {
    let macApp: MacApp

    private init(_ id: UInt32, _ app: MacApp, workspace: Workspace, kind: WindowKind, size: CGSize?) {
        macApp = app
        super.init(id: id, app, workspace: workspace, kind: kind, lastFloatingSize: size)
    }

    static var allWindows: [MacWindow] { DisplayLayoutState.shared.allWindows.compactMap { $0 as? MacWindow } }

    @discardableResult
    static func getOrRegister(windowId: UInt32, macApp: MacApp) async throws -> MacWindow {
        if let existing = Window.get(byId: windowId) as? MacWindow { return existing }
        let rect = try await macApp.getAxRect(windowId, .cancellable)
        let kind = try await classifyWindow(windowId, macApp, .cancellable)
        // AX reads suspend. Resolve identity and display membership again before publishing.
        if let existing = Window.get(byId: windowId) as? MacWindow { return existing }
        let workspace = (rect?.center.monitorApproximation ?? focus.workspace.workspaceMonitor).activeWorkspace
        let window = MacWindow(windowId, macApp, workspace: workspace, kind: kind, size: rect?.size)
        window.layoutState.restoreWindow(newlyDetectedWindow: window)
        return window
    }

    func isWindowHeuristic(_ windowLevel: MacOsWindowLevel?, _ cm: CancellationMode) async throws -> Bool {  // todo cache
        try await macApp.isWindowHeuristic(windowId, windowLevel, cm)
    }

    // skipClosedWindowsCache is an optimization when it's definitely not necessary to cache closed window.
    //                        If you are unsure, it's better to pass `false`
    @MainActor
    func garbageCollect(skipClosedWindowsCache: Bool) {
        layoutState.removeWindow(self, remember: !skipClosedWindowsCache)?.nativeFocus()
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

extension MacWindow {
    func reclassify(on workspace: Workspace, _ cm: CancellationMode) async throws {
        let kind = try await classifyWindow(windowId, macApp, cm)
        guard isRegistered, self.kind == .popup else { return }
        layoutState.place(self, on: workspace, kind: kind)
    }
}

@MainActor private func classifyWindow(_ id: UInt32, _ app: MacApp, _ cm: CancellationMode) async throws -> WindowKind {
    let type = try await app.getAxUiElementWindowType(id, getWindowLevel(for: id), cm)
    if type != .popup, config.floatingApps.contains(app.rawAppBundleId ?? "") { return .floating }
    return switch type {
    case .popup: .popup
    case .dialog: .floating
    case .window: .tiled
    }
}
