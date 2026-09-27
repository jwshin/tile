import Common

struct SwapCommand: Command {
    let direction: CardinalDirection
    let invalidatesRestoration = true

    func run(_ io: CmdIo) async -> BinaryExitCode {
        guard let window = focus.windowOrNil, window.kind == .tiled, let workspace = window.workspace else {
            return .fail(io.err("Swap requires a focused tiled window"))
        }
        guard let target = await workspace.neighbor(of: window, direction: direction, tiledOnly: true) else {
            return .succ
        }
        workspace.layout.swap(window.windowId, target.windowId)
        return .from(bool: window.focusWindow())
    }
}
