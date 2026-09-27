import AppKit
import Common
import Foundation
import HotKey
import Testing

@testable import AppBundle

let projectRoot: URL = {
    var url = URL(filePath: #filePath).absoluteURL
    check(FileManager.default.fileExists(atPath: url.path))
    while !FileManager.default.fileExists(atPath: url.appending(component: ".git").path) {
        url.deleteLastPathComponent()
    }
    return url
}()

@MainActor
func setUpWorkspacesForTests() {
    config = defaultConfig

    config.bindings = [:]
    testWorkspaceAliases = [:]
    unsafe testMonitors = [TestMonitor(displayId: "test-main", name: "Main", x: 0, isMain: true)]
    for workspace in Workspace.all {
        for child in workspace.children { child.unbindFromParent() }
    }
    Workspace.reconcileMonitors(monitorInfos)
    _ = mainMonitorInfo.activeWorkspace.focusWorkspace()
    resetClosedWindowsCache()

    TestApp.shared.focusedWindow = nil
    TestApp.shared.windows = []
}

struct TestMonitor: MonitorInfo {
    let displayId: String
    let name: String
    let x: Double
    var isMain: Bool = false
    var width: CGFloat = 1920
    var height: CGFloat = 1080
    var rect: Rect { Rect(topLeftX: x, topLeftY: 0, width: width, height: height) }
    var visibleRect: Rect { rect }
}

@MainActor private var testWorkspaceAliases: [String: Workspace] = [:]

/// Map legacy tree fixtures to real display layouts rather than named virtual workspaces.
@MainActor func workspaceForTest(_ name: String) -> Workspace {
    if let existing = testWorkspaceAliases[name] { return existing }
    let workspace: Workspace
    if testWorkspaceAliases.isEmpty {
        workspace = mainMonitorInfo.activeWorkspace
    } else {
        let monitor = TestMonitor(displayId: name, name: name, x: Double(monitorInfos.count) * 1920)
        unsafe testMonitors = monitorInfos + [monitor]
        Workspace.reconcileMonitors(monitorInfos)
        workspace = monitor.activeWorkspace
    }
    testWorkspaceAliases[name] = workspace
    return workspace
}
