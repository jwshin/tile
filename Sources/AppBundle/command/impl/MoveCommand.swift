import AppKit
import Common

struct MoveCommand: Command {
    let direction: CardinalDirection
    let invalidatesRestoration = true

    func run(_ io: CmdIo) async -> BinaryExitCode {
        guard let window = focus.windowOrNil, let workspace = window.workspace else { return .fail }
        if window.kind == .floating {
            guard let rect = try? await window.getAxRect(.nonCancellable), window.isRegistered,
                window.workspace === workspace, window.kind == .floating
            else { return .fail }
            let amount: CGFloat = direction.isPositive ? 50 : -50
            let bounds = workspace.workspaceMonitor.visibleRect
            let point = CGPoint(
                x: min(
                    max(bounds.minX, rect.minX + (direction.orientation == .h ? amount : 0)),
                    max(bounds.minX, bounds.maxX - rect.width)),
                y: min(
                    max(bounds.minY, rect.minY + (direction.orientation == .v ? amount : 0)),
                    max(bounds.minY, bounds.maxY - rect.height)))
            window.setAxFrame(point, nil)
            return .succ
        }
        guard window.kind == .tiled else { return .fail }
        workspace.layout.move(
            window.windowId, direction: direction, in: workspace.layoutRect,
            gap: CGFloat(config.gap), minimums: workspace.minimums)
        return .from(bool: window.focusWindow())
    }
}
