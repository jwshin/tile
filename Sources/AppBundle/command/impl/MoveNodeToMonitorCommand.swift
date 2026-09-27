import Common

struct MoveNodeToMonitorCommand: Command {
    let target: MonitorTarget
    let invalidatesRestoration = true

    func run(_ io: CmdIo) -> BinaryExitCode {
        guard let window = focus.windowOrNil, let workspace = window.workspace,
            window.kind == .tiled || window.kind == .floating
        else {
            return .fail(io.err("Move to monitor requires a tiled or floating window"))
        }
        switch target.resolve(workspace.workspaceMonitor) {
        case .success(let monitor):
            let destination = monitor.activeWorkspace
            if destination !== workspace { window.layoutState.place(window, on: destination, kind: window.kind) }
            return .from(bool: window.focusWindow())
        case .failure(let message): return .fail(io.err(message))
        }
    }
}
