import Common

struct FullscreenCommand: Command {
    let shouldResetClosedWindowsCache = false

    func run(_ io: CmdIo) -> BinaryExitCode {
        guard let window = focus.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }
        window.isFullscreen.toggle()
        window.markAsMostRecentChild()
        return .succ
    }
}

let noWindowIsFocused = "No window is focused"
