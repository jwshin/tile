import AppKit
import Common

@MainActor struct NativeDesktopSessionAdapter: DesktopSessionAdapter {
    func focusedWindow() async throws -> Window? {
        let focused = try await getNativeFocusedWindow(.cancellable)
        if let window = focused as? MacWindow, window.kind != .popup {
            window.macApp.lastNativeFocusedWindowId = window.windowId
        }
        return focused
    }

    func validatePopups() async throws {
        for popup in MacWindow.allWindows where popup.kind == .popup {
            let windowLevel = getWindowLevel(for: popup.windowId)
            if try await popup.isWindowHeuristic(windowLevel, .cancellable) {
                try await popup.reclassify(on: focus.workspace, .cancellable)
            }
        }
    }

    func updateStatus() { updateTrayStatus() }

    func refreshWindows() async throws {
        // Garbage collect terminated apps and windows before working with all windows
        let mapping = try await MacApp.refreshAllAndGetAliveWindowIds(
            frontmostAppBundleId: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        let aliveWindowIds = mapping.values.flatMap(id).toSet()

        for window in MacWindow.allWindows {
            if !aliveWindowIds.contains(window.windowId) {
                window.garbageCollect(skipClosedWindowsCache: false)
            }
        }
        for (app, windowIds) in mapping {
            for windowId in windowIds {
                try await MacWindow.getOrRegister(windowId: windowId, macApp: app)
            }
        }
    }
}

func refreshObs(_: AXObserver, _: AXUIElement, notif: CFString, _: UnsafeMutableRawPointer?) {
    let notif = notif as String
    _ = Task { @MainActor in
        if !TrayMenuModel.shared.isEnabled { return }
        ActionExecution.shared.scheduleRefresh(.ax(notif))
    }
}
