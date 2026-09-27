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

    /// Spatial navigation includes floating windows without inserting them into the tree.
    func neighbor(of window: Window, direction: CardinalDirection, tiledOnly: Bool = false) async -> Window? {
        var floatingFrames: [UInt32: Rect] = [:]
        if !tiledOnly {
            for candidate in floatingWindows {
                if let rect = try? await candidate.getAxRect(.nonCancellable), candidate.isRegistered,
                    candidate.workspace === self, candidate.kind == .floating
                {
                    floatingFrames[candidate.windowId] = rect
                }
            }
        }
        guard window.isRegistered, window.workspace === self else { return nil }
        var frames = tiledFrames.merging(floatingFrames) { tiled, _ in tiled }
        let valid = Set(windows.filter { $0.kind == .tiled || (!tiledOnly && $0.kind == .floating) }.map(\.windowId))
        frames = frames.filter { valid.contains($0.key) }
        return directionalNeighbor(of: window.windowId, direction: direction, frames: frames).flatMap {
            state.window(for: $0)
        }
    }
}

/// Prefer candidates overlapping on the perpendicular axis, then distance, then stable identity.
func directionalNeighbor(of id: UInt32, direction: CardinalDirection, frames: [UInt32: Rect]) -> UInt32? {
    guard let origin = frames[id] else { return nil }
    let axis = direction.orientation
    let perpendicular = axis.opposite
    let originCenter = origin.center.getProjection(axis)
    let crossCenter = origin.center.getProjection(perpendicular)
    let originHalf = origin.getDimension(perpendicular) / 2
    return frames.compactMap { candidate, rect -> (UInt32, Int, CGFloat, CGFloat)? in
        guard candidate != id else { return nil }
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
