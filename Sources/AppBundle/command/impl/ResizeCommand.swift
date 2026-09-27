import AppKit
import Common

struct ResizeCommand: Command {
    let grow: Bool
    let invalidatesRestoration = true

    func run(_ io: CmdIo) -> BinaryExitCode {
        guard let window = focus.windowOrNil, window.kind == .tiled, let workspace = window.workspace else {
            return .fail(io.err("Resize requires a focused tiled window"))
        }
        return .from(
            bool: workspace.layout.resize(
                window.windowId, by: grow ? 50 : -50,
                in: workspace.layoutRect, gap: CGFloat(config.gap)))
    }
}
