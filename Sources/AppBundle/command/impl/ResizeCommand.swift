import AppKit
import Common

struct ResizeCommand: Command {
    let grow: Bool
    let invalidatesRestoration = true

    func run(_ io: CmdIo) -> BinaryExitCode {
        guard let window = focus.windowOrNil, let parent = window.parent as? TilingContainer else {
            return .fail(io.err("Resize requires a focused tiling window"))
        }
        let diff: CGFloat = grow ? 50 : -50
        guard let childDiff = diff.div(parent.children.count - 1) else { return .fail }
        for sibling in parent.children where sibling != window {
            sibling.setWeight(parent.orientation, sibling.getWeight(parent.orientation) - childDiff)
        }
        window.setWeight(parent.orientation, window.getWeight(parent.orientation) + diff)
        return .succ
    }
}
