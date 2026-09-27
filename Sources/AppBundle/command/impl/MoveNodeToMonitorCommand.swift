import AppKit
import Common

struct MoveNodeToMonitorCommand: Command {
    let target: MonitorTarget
    let shouldResetClosedWindowsCache = true

    func run(_ io: CmdIo) -> BinaryExitCode {
        guard let window = focus.windowOrNil else {
            return .fail(io.err(noWindowIsFocused))
        }
        guard let currentMonitor = window.nodeMonitor else {
            return .fail(io.err(windowIsntPartOfTree(window)))
        }
        switch target.resolve(currentMonitor) {
        case .success(let targetMonitor):
            let targetWs = targetMonitor.activeWorkspace
            let index =
                true
                    == target.directionOrNil
                    .map { dir in dir.isPositive && targetWs.rootTilingContainer.orientation == dir.orientation }
                ? 0
                : INDEX_BIND_LAST
            if window.nodeWorkspace == targetWs { return .succ }
            let container: NonLeafTreeNodeObject =
                window.isFloating
                ? targetWs.floatingWindowsContainer : targetWs.rootTilingContainer
            window.bind(to: container, adaptiveWeight: WEIGHT_AUTO, index: index)
            return .from(bool: window.focusWindow())
        case .failure(let msg):
            return .fail(io.err(msg))
        }
    }
}

func windowIsntPartOfTree(_ window: Window) -> String {
    "Window \(window.windowId) is not part of tree (minimized or hidden)"
}
