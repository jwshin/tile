import Common

struct CloseCommand: Command {
    let shouldResetClosedWindowsCache = false

    func run(_ io: CmdIo) -> BinaryExitCode {
        guard let window = focus.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }
        window.closeAxWindow()
        return .succ
    }
}
