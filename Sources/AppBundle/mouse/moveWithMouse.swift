import AppKit
import Common

func movedObs(_: AXObserver, ax: AXUIElement, notif: CFString, _: UnsafeMutableRawPointer?) {
    observeMouseChange(windowId: ax.containingWindowId(), notification: notif as String, resizing: false)
}

func resizedObs(_: AXObserver, ax: AXUIElement, notif: CFString, _: UnsafeMutableRawPointer?) {
    observeMouseChange(windowId: ax.containingWindowId(), notification: notif as String, resizing: true)
}

private func observeMouseChange(windowId: UInt32?, notification: String, resizing: Bool) {
    _ = Task { @MainActor in
        guard let token: RunSessionGuard = .isEnabled else { return }
        guard let windowId, let window = Window.get(byId: windowId), try await isManipulatedWithMouse(window) else {
            ActionExecution.shared.scheduleRefresh(.ax(notification))
            return
        }
        try await ActionExecution.shared.runSession(.ax(notification), token) {
            guard let rect = try await window.getAxRect(.cancellable), window.isRegistered,
                isLeftMouseButtonDown, ConfigurationApplication.shared.isEnabled
            else { return }
            await DisplayLayoutState.shared.changeLayout {
                switch window.kind {
                case .floating:
                    let destination = rect.center.monitorApproximation.activeWorkspace
                    if window.workspace !== destination { window.bindAsFloatingWindow(to: destination) }
                case .tiled:
                    MouseTiling.shared.observe(window, frame: rect, resizing: resizing)
                    let point = mouseLocation
                    MouseTiling.shared.drag(at: point, on: point.monitorApproximation.activeWorkspace)
                default: break
                }
            }
        }
    }
}

@MainActor func resetManipulatedWithMouseIfPossible() async throws {
    guard currentlyManipulatedWithMouseWindowId != nil else { return }
    let point = mouseLocation
    await DisplayLayoutState.shared.changeLayout {
        MouseTiling.shared.finish(at: point, on: point.monitorApproximation.activeWorkspace)
    }
    ActionExecution.shared.scheduleRefresh(.resetManipulatedWithMouse)
}
