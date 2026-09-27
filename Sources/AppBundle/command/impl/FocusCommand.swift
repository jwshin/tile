import Common

struct FocusCommand: Command {
    let direction: CardinalDirection
    let invalidatesRestoration = false

    func run(_ io: CmdIo) async -> BinaryExitCode {
        let target = focus
        guard let window = target.windowOrNil,
            let neighbor = await target.workspace.neighbor(of: window, direction: direction)
        else { return .succ }
        return .from(bool: neighbor.focusWindow())
    }
}
