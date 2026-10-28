@MainActor @discardableResult
func normalizeLayoutReason() async throws -> Bool {
    let state = DisplayLayoutState.shared
    let generation = state.lifecycleGeneration
    try state.checkLifecycle(generation)
    var restored = false
    for window in state.allWindows where window.kind != .popup {
        let observation = try await window.isMacosFullscreen(.cancellable)
        try state.checkLifecycle(generation)
        guard let fullscreen = observation else {
            window.cancelPendingFrame()
            continue
        }
        let minimized = fullscreen ? false : try await window.isMacosMinimized(.cancellable)
        try state.checkLifecycle(generation)
        guard window.isRegistered, let workspace = window.workspace else { continue }
        if fullscreen { window.cancelPendingFrame() }
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
