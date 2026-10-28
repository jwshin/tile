import AppKit

extension Workspace {
    func layoutWorkspace(preservingPointerWindow pendingWindow: Window? = nil) async throws {
        guard !state.isRecoveringDisplays else { return }
        let generation = state.lifecycleGeneration
        recover()
        for window in tiledWindows {
            if state.manipulatedWindow === window || pendingWindow === window {
                window.cancelPendingFrame()
                continue
            }
            let fullscreen = try await window.isMacosFullscreen(.cancellable)
            try state.checkLifecycle(generation)
            guard window.isRegistered, window.workspace === self, window.kind == .tiled else { continue }
            guard fullscreen == false else {
                window.cancelPendingFrame()
                continue
            }
            if state.manipulatedWindow === window || pendingWindow === window {
                window.cancelPendingFrame()
                continue
            }
            // Native reads suspend; use the current allocation after any intervening action.
            guard let rect = tiledFrames[window.windowId] else { continue }
            if window.isFullscreen && window.windowId == insertionTarget {
                window.lastAppliedLayoutPhysicalRect = nil
                let full = workspaceMonitor.visibleRectPaddedByOuterGaps
                window.setAxFrame(full.topLeftCorner, full.size)
            } else {
                window.isFullscreen = false
                window.lastAppliedLayoutPhysicalRect = rect
                window.setAxFrame(rect.topLeftCorner, rect.size)
            }
        }
        for window in floatingWindows {
            if state.manipulatedWindow === window || pendingWindow === window {
                window.cancelPendingFrame()
                continue
            }
            let fullscreen = try await window.isMacosFullscreen(.cancellable)
            try state.checkLifecycle(generation)
            guard fullscreen == false else {
                window.cancelPendingFrame()
                continue
            }
            if state.manipulatedWindow === window || pendingWindow === window {
                window.cancelPendingFrame()
                continue
            }
            try await window.layoutFloatingWindow(on: self)
        }
    }
}

extension Window {
    fileprivate func layoutFloatingWindow(on workspace: Workspace) async throws {
        let generation = layoutState.lifecycleGeneration
        let rect = try await getAxRect(.cancellable)
        try layoutState.checkLifecycle(generation)
        guard isRegistered, self.workspace === workspace, kind == .floating else { return }
        if let rect {
            lastAppliedLayoutPhysicalRect = rect
            let current = rect.center.monitorApproximation
            let destination = workspace.workspaceMonitor.visibleRect
            if current.displayId != workspace.name || !destination.contains(rect.center) {
                let x = (rect.minX - current.visibleRect.minX) / max(1, current.visibleRect.width)
                let y = (rect.minY - current.visibleRect.minY) / max(1, current.visibleRect.height)
                let point = CGPoint(
                    x: min(
                        max(destination.minX, destination.minX + x * destination.width),
                        max(destination.minX, destination.maxX - rect.width)),
                    y: min(
                        max(destination.minY, destination.minY + y * destination.height),
                        max(destination.minY, destination.maxY - rect.height)))
                setAxFrame(point, nil)
            }
        }
        if isFullscreen {
            let full = workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
            setAxFrame(full.topLeftCorner, full.size)
            isFullscreen = false
        }
    }
}
