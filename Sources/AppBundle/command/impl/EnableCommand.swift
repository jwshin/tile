import AppKit
import Common

struct EnableCommand: Command {
    let invalidatesRestoration = false

    func run(_ io: CmdIo) async -> BinaryExitCode {
        let application = ConfigurationApplication.shared
        let newState = !application.isEnabled
        // Publish before an AX read can suspend, so a later toggle observes this transition.
        application.setEnabled(newState)
        if newState {
            for workspace in DisplayLayoutState.shared.workspaces {
                for window in workspace.allLeafWindowsRecursive where window.isFloating {
                    window.lastFloatingSize = (try? await window.getAxSize(.nonCancellable)) ?? window.lastFloatingSize
                }
            }
        }
        return .succ
    }
}
