import Common

struct SwapCommand: Command {
    let direction: CardinalDirection
    let shouldResetClosedWindowsCache = true

    func run(_ io: CmdIo) -> BinaryExitCode {
        guard let window = focus.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }
        guard let (parent, index) = window.closestParent(hasChildrenInDirection: direction),
            let other = parent.children[index + direction.focusOffset]
                .findLeafWindowRecursive(snappedTo: direction.opposite)
        else { return .fail }
        swapWindows(mruDominant: window, other)
        return .succ
    }
}
