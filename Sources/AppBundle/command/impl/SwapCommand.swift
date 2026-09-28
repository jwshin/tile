import AppKit
import Common

struct SwapCommand: Command {
    let direction: CardinalDirection
    let invalidatesRestoration = true

    func run(_ io: CmdIo) async -> BinaryExitCode {
        guard let window = focus.windowOrNil, window.kind == .tiled, let workspace = window.workspace else {
            return .fail(io.err("Swap requires a focused tiled window"))
        }
        workspace.layout.move(
            window.windowId, direction: direction, in: workspace.layoutRect,
            gap: CGFloat(config.gap), minimums: workspace.minimums, windowOnly: true)
        return .from(bool: window.focusWindow())
    }
}
