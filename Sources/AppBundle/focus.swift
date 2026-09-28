import AppKit
import Common

struct LiveFocus: Equatable {
    let windowOrNil: Window?
    var workspace: Workspace
    @MainActor var frozen: FrozenFocus { FrozenFocus(windowId: windowOrNil?.windowId, workspaceName: workspace.name) }
}

@MainActor var focus: LiveFocus { DisplayLayoutState.shared.focus }

extension Window {
    func focusWindow() -> Bool {
        guard let live = toLiveFocusOrNil() else { return false }
        return layoutState.setFocus(to: live)
    }
    func toLiveFocusOrNil() -> LiveFocus? {
        guard isRegistered, isFocusable, let workspace else { return nil }
        return LiveFocus(windowOrNil: self, workspace: workspace)
    }
}
extension Workspace {
    func focusWorkspace() -> Bool { state.setFocus(to: toLiveFocus()) }
    func toLiveFocus() -> LiveFocus { LiveFocus(windowOrNil: mostRecentWindow, workspace: self) }

    /// Directional focus stays on this screen while a tile is available, then crosses screens.
    func neighbor(of window: Window, direction: CardinalDirection) async -> Window? {
        var origin = tiledFrames[window.windowId]
        if origin == nil { origin = try? await window.getAxRect(.nonCancellable) }
        guard window.isRegistered, window.workspace === self, let origin else { return nil }
        var frames = tiledFrames
        frames[window.windowId] = origin
        if let id = directionalNeighbor(of: window.windowId, direction: direction, frames: frames) {
            return state.window(for: id)
        }
        var external: [UInt32: Rect] = [window.windowId: origin]
        for workspace in state.workspaces where workspace !== self {
            external.merge(workspace.tiledFrames) { current, _ in current }
        }
        return directionalNeighbor(of: window.windowId, direction: direction, frames: external).flatMap {
            state.window(for: $0)
        }
    }
}

/// Prefer candidates overlapping on the perpendicular axis, then distance, then stable identity.
func directionalNeighbor(of id: UInt32, direction: CardinalDirection, frames: [UInt32: Rect]) -> UInt32? {
    guard let origin = frames[id] else { return nil }
    return directionalNeighbor(from: origin, direction: direction, candidates: frames.filter { $0.key != id })
}

func directionalNeighbor(from origin: Rect, direction: CardinalDirection, candidates: [UInt32: Rect]) -> UInt32? {
    let axis = direction.orientation
    let perpendicular = axis.opposite
    let originCenter = origin.center.getProjection(axis)
    let crossCenter = origin.center.getProjection(perpendicular)
    let originHalf = origin.getDimension(perpendicular) / 2
    return candidates.compactMap { candidate, rect -> (UInt32, Int, CGFloat, CGFloat)? in
        let forward = (rect.center.getProjection(axis) - originCenter) * (direction.isPositive ? 1 : -1)
        guard forward > 0 else { return nil }
        let cross = abs(rect.center.getProjection(perpendicular) - crossCenter)
        let overlaps = cross < originHalf + rect.getDimension(perpendicular) / 2
        return (candidate, overlaps ? 0 : 1, forward, cross)
    }.min { a, b in
        if a.1 != b.1 { return a.1 < b.1 }
        if a.2 != b.2 { return a.2 < b.2 }
        if a.3 != b.3 { return a.3 < b.3 }
        return a.0 < b.0
    }?.0
}
