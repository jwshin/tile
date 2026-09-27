import Common

final class CmdIo {
    var stdout: [String] = []
    var stderr: [String] = []

    @discardableResult func out(_ message: String) -> IoSideEffect {
        stdout.append(message)
        return .instance
    }
    @discardableResult func err(_ message: String) -> IoSideEffect {
        stderr.append(message)
        return .instance
    }
}

struct CmdResult: Equatable {
    let stdout: [String]
    let stderr: [String]
    let exitCode: BinaryExitCode
    var diagnostics: String { (stderr + stdout).joined(separator: "\n") }
}
