import Common

protocol CmdIo: AnyObject {
    var stdout: [String] { get set }
    var stderr: [String] { get set }
}

extension CmdIo {
    @discardableResult func out(_ message: String) -> IoSideEffect {
        stdout.append(message)
        return .instance
    }
    @discardableResult func err(_ message: String) -> IoSideEffect {
        stderr.append(message)
        return .instance
    }
}

final class CmdIoImpl: CmdIo {
    var stdout: [String] = []
    var stderr: [String] = []
}

struct CmdResult: Equatable {
    let stdout: [String]
    let stderr: [String]
    let exitCode: BinaryExitCode
    var diagnostics: String { (stderr + stdout).joined(separator: "\n") }
}
