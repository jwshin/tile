import Common

protocol Command: Sendable {
    @MainActor func run(_ io: CmdIo) async -> BinaryExitCode
    var invalidatesRestoration: Bool { get }
}
