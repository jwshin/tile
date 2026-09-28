@MainActor @discardableResult
func normalizeLayoutReason() async throws -> Bool {
    var restored = false
    for window in DisplayLayoutState.shared.allWindows where window.kind != .popup {
        let fullscreen = try await window.isMacosFullscreen(.cancellable)
        let minimized = fullscreen ? false : try await window.isMacosMinimized(.cancellable)
        guard window.isRegistered, let workspace = window.workspace else { continue }
        let nativeKind: WindowKind? =
            fullscreen ? .nativeFullscreen : minimized ? .minimized : window.app.isHidden ? .hidden : nil
        if let nativeKind {
            if window.kind == .tiled || window.kind == .floating { window.resumeKind = window.kind }
            if window.kind != nativeKind { window.layoutState.place(window, on: workspace, kind: nativeKind) }
        } else if window.kind == .nativeFullscreen || window.kind == .minimized || window.kind == .hidden {
            window.layoutState.place(window, on: workspace, kind: window.resumeKind)
            restored = true
        }
    }
    return restored
}
