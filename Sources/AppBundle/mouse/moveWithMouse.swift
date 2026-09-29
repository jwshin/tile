import AppKit
import Common

func movedObs(_: AXObserver, ax: AXUIElement, notif: CFString, _: UnsafeMutableRawPointer?) {
    observeMouseChange(windowId: ax.containingWindowId(), notification: notif as String)
}

func resizedObs(_: AXObserver, ax: AXUIElement, notif: CFString, _: UnsafeMutableRawPointer?) {
    observeMouseChange(windowId: ax.containingWindowId(), notification: notif as String)
}

private func observeMouseChange(windowId: UInt32?, notification: String) {
    _ = Task { @MainActor in
        guard let token: RunSessionGuard = .isEnabled else { return }
        guard let windowId, let window = Window.get(byId: windowId), try await isManipulatedWithMouse(window) else {
            ActionExecution.shared.scheduleRefresh(.ax(notification))
            return
        }
        try await ActionExecution.shared.runSession(.ax(notification), token) {
            guard let rect = try await window.getAxRect(.cancellable), window.isRegistered,
                window.layoutState.isPointerDown, ConfigurationApplication.shared.isEnabled
            else { return }
            let point = mouseLocation
            window.layoutState.updatePointer(
                window, frame: rect, at: point,
                on: window.layoutState.workspace(for: point.monitorApproximation))
        }
    }
}

@MainActor func resetManipulatedWithMouseIfPossible() async throws {
    let state = DisplayLayoutState.shared
    guard state.isHandlingPointer else { return }
    let point = mouseLocation
    state.finishPointer(at: point, on: state.workspace(for: point.monitorApproximation))
    ActionExecution.shared.scheduleRefresh(.resetManipulatedWithMouse)
}
