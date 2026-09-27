import AppKit
import Common

struct FlattenWorkspaceTreeCommand: Command {
    let invalidatesRestoration: Bool = true

    func run(_ io: CmdIo) -> BinaryExitCode {
        let target = focus
        let workspace = target.workspace
        let windows = workspace.rootTilingContainer.allLeafWindowsRecursive
        for window in windows {
            window.bind(to: workspace.rootTilingContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        }
        return .succ
    }
}
