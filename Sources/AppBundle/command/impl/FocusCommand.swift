import Common

struct FocusCommand: Command {
    let direction: CardinalDirection
    let invalidatesRestoration = false

    func run(_ io: CmdIo) async -> BinaryExitCode {
        let target = focus
        let neighbor: Window?
        if let window = target.windowOrNil {
            neighbor = await target.workspace.neighbor(of: window, direction: direction)
        } else {
            let frames = target.workspace.state.workspaces.reduce(into: [UInt32: Rect]()) { frames, workspace in
                frames.merge(workspace.tiledFrames) { current, _ in current }
            }
            neighbor = directionalNeighbor(from: target.workspace.layoutRect, direction: direction, candidates: frames)
                .flatMap { target.workspace.state.window(for: $0) }
        }
        guard let neighbor else { return .succ }
        return .from(bool: neighbor.focusWindow())
    }
}
