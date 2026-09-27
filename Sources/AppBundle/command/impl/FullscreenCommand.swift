import Common

struct FullscreenCommand: Command {
    let invalidatesRestoration = false

    func run(_ io: CmdIo) -> BinaryExitCode {
        guard let window = focus.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }
        window.isFullscreen.toggle()
        window.markRecent()
        return .succ
    }
}

let noWindowIsFocused = "No window is focused"
