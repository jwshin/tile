import Common

struct ReloadConfigCommand: Command {
    let invalidatesRestoration = false

    func run(_ io: CmdIo) async -> BinaryExitCode {
        let result = ConfigurationApplication.shared.reload()
        if let diagnostics = result.diagnostics { io.err(diagnostics) }
        return .from(bool: result.isOk)
    }
}
