import AppKit
import Common

struct EnableCommand: Command {
    let shouldResetClosedWindowsCache = false

    func run(_ io: CmdIo) async -> BinaryExitCode {
        let newState = !TrayMenuModel.shared.isEnabled
        TrayMenuModel.shared.isEnabled = newState
        if newState {
            for workspace in Workspace.all {
                for window in workspace.allLeafWindowsRecursive where window.isFloating {
                    window.lastFloatingSize = (try? await window.getAxSize(.nonCancellable)) ?? window.lastFloatingSize
                }
            }
            syncHotkeys()
        } else {
            resetHotKeys()
        }
        return .succ
    }
}
