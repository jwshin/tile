import AppKit
import Common

struct MoveCommand: Command {
    let direction: CardinalDirection
    let invalidatesRestoration = true

    func run(_ io: CmdIo) async -> BinaryExitCode {
        guard let window = focus.windowOrNil, window.kind == .tiled, let workspace = window.workspace else {
            return .fail(io.err("Move requires a focused tiled window"))
        }
        guard let target = await workspace.neighbor(of: window, direction: direction, tiledOnly: true) else {
            return .succ
        }
        workspace.layout.move(
            window.windowId, beside: target.windowId, direction: direction,
            in: workspace.layoutRect, gap: CGFloat(config.gap))
        return .from(bool: window.focusWindow())
    }
}
