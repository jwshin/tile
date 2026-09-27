import Common

protocol Command: Sendable {
    @MainActor func run(_ io: CmdIo) async -> BinaryExitCode
    var shouldResetClosedWindowsCache: Bool { get }
}

extension Command {
    @MainActor @discardableResult
    func run() async -> CmdResult {
        let io = CmdIoImpl()
        let result = await run(io)
        if shouldResetClosedWindowsCache { resetClosedWindowsCache() }
        await refreshModel_nonCancellable()
        return CmdResult(stdout: io.stdout, stderr: io.stderr, exitCode: result)
    }
}
