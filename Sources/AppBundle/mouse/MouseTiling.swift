import AppKit
import Common

/// One drag/resize gesture. A value snapshot prevents cumulative deltas and stale edits.
@MainActor final class MouseTiling {
    static let shared = MouseTiling()
    private struct Gesture {
        let window: Window
        var workspace: Workspace
        let original: BinaryLayout
        let frame: Rect
        var bounds: Rect
        let gap: CGFloat
        var expected: BinaryLayout
        var resizing = false
        var hasRearranged = false
        var lastTargetRegion: Rect?
    }
    private var gesture: Gesture?

    func cancel() {
        gesture = nil
        currentlyManipulatedWithMouseWindowId = nil
    }

    func observe(_ window: Window, frame: Rect, resizing: Bool) {
        guard window.isRegistered, window.kind == .tiled, let workspace = window.workspace else { return }
        if gesture == nil {
            guard let originalFrame = window.lastAppliedLayoutPhysicalRect ?? workspace.tiledFrames[window.windowId]
            else { return }
            gesture = Gesture(
                window: window, workspace: workspace, original: workspace.layout,
                frame: originalFrame, bounds: workspace.layoutRect, gap: CGFloat(config.gap), expected: workspace.layout
            )
        }
        guard var current = validGesture(), current.window === window else { return }
        currentlyManipulatedWithMouseWindowId = window.windowId
        current.resizing =
            current.resizing
            || (!current.hasRearranged && resizing
                && (abs(frame.width - current.frame.width) > 5 || abs(frame.height - current.frame.height) > 5))
        if current.resizing {
            var layout = current.original
            let edges: [(CardinalDirection, CGFloat)] = [
                (.left, frame.minX - current.frame.minX), (.right, frame.maxX - current.frame.maxX),
                (.up, frame.minY - current.frame.minY), (.down, frame.maxY - current.frame.maxY),
            ]
            for (edge, delta) in edges where abs(delta) > 5 {
                layout.resizeEdge(window.windowId, edge: edge, by: delta, in: current.bounds, gap: current.gap)
            }
            workspace.layout = layout
            current.expected = layout
        }
        gesture = current
    }

    private func validGesture() -> Gesture? {
        guard let current = gesture else { return nil }
        guard current.window.isRegistered, current.window.kind == .tiled,
            current.window.workspace === current.workspace,
            current.window.layoutState.contains(current.workspace),
            current.expected == current.workspace.layout,
            current.bounds.size == current.workspace.layoutRect.size,
            current.bounds.topLeftCorner == current.workspace.layoutRect.topLeftCorner,
            current.gap == CGFloat(config.gap)
        else {
            cancel()
            return nil
        }
        return current
    }

    func drag(at point: CGPoint, on destination: Workspace) {
        guard var current = validGesture(), !current.resizing,
            current.window.layoutState.contains(destination)
        else { return }
        // Layout changes move hit regions beneath the pointer. Wait until it leaves the
        // previous region before choosing another target, including at mouse release.
        if destination === current.workspace, current.lastTargetRegion?.contains(point) == true { return }
        current.lastTargetRegion = nil
        gesture = current
        let window = current.window
        let hit = destination.tiledFrames.sorted { $0.key < $1.key }.first { $0.value.contains(point) }
        if let (target, rect) = hit {
            guard target != window.windowId else { return }
            current.lastTargetRegion = rect
            let x = (point.x - rect.minX) / max(1, rect.width)
            let y = (point.y - rect.minY) / max(1, rect.height)
            if destination === current.workspace, x > 0.25, x < 0.75, y > 0.25, y < 0.75 {
                destination.layout.swap(window.windowId, target)
            } else {
                let edge: CardinalDirection =
                    abs(x - 0.5) > abs(y - 0.5) ? (x < 0.5 ? .left : .right) : (y < 0.5 ? .up : .down)
                window.layoutState.place(window, on: destination, kind: .tiled, beside: target, direction: edge)
            }
        } else if destination !== current.workspace {
            window.layoutState.place(window, on: destination, kind: .tiled)
            current.lastTargetRegion = destination.layoutRect
        } else {
            return
        }
        current.workspace = destination
        current.expected = destination.layout
        current.bounds = destination.layoutRect
        current.hasRearranged = true
        gesture = current
        _ = window.focusWindow()
    }

    func finish(at point: CGPoint, on destination: Workspace) {
        defer { cancel() }
        drag(at: point, on: destination)
    }
}
