import Common

struct BalanceSizesCommand: Command {
    let invalidatesRestoration = true
    func run(_ io: CmdIo) -> BinaryExitCode {
        focus.workspace.layout.balance()
        return .succ
    }
}
