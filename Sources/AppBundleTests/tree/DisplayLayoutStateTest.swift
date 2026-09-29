import AppKit
import Common
import Testing

@testable import AppBundle

extension CoreTests {
    @MainActor struct DisplayLayoutStateTest {
        init() { setUpWorkspacesForTests() }
        private let main = TestMonitor(displayId: "main", name: "Main", x: 0, isMain: true)
        private let side = TestMonitor(displayId: "side", name: "Side", x: 1920)

        @Test func insertionUsesLogicalFocusEvenWhenAnotherWindowWasJustRegistered() {
            let workspace = focus.workspace
            let focused = TestWindow.new(id: 1, workspace: workspace)
            _ = focused.focusWindow()
            TestWindow.new(id: 2, workspace: workspace)
            let rightFrame = workspace.tiledFrames[2]
            TestWindow.new(id: 3, workspace: workspace)
            #expect(workspace.tiledFrames[2]?.size == rightFrame?.size)
            #expect(workspace.tiledFrames[2]?.topLeftCorner == rightFrame?.topLeftCorner)
            #expect(workspace.layout.windowIds == [1, 3, 2])
        }

        @Test func restoredNativeWindowRemembersItWasFloating() async {
            let state = DisplayLayoutState.shared
            let old = TestWindow.new(id: 1, workspace: state.mainWorkspace, kind: .floating)
            TestApp.shared.isHidden = true
            await normalizeForTest()
            #expect(old.kind == .hidden && old.resumeKind == .floating)
            state.removeWindow(old, remember: true)
            let returned = TestWindow.new(id: 1, workspace: state.mainWorkspace)
            #expect(state.restoreWindow(newlyDetectedWindow: returned))
            #expect(returned.kind == .hidden && returned.resumeKind == .floating)
            TestApp.shared.isHidden = false
            await normalizeForTest()
            #expect(returned.kind == .floating)
            #expect(state.mainWorkspace.layout.windowIds.isEmpty)
        }

        private func normalizeForTest() async {
            await ActionExecution(desktop: TestDesktopSessionAdapter()).refresh(.startup, assumeCancellable: false)
        }

        @Test func ownersDoNotShareLayoutsFocusOrWindowIdentity() {
            let first = DisplayLayoutState(monitors: [main, side], pointer: TestPointerAdapter())
            let second = DisplayLayoutState(monitors: [main, side], pointer: TestPointerAdapter())
            let a = TestWindow.new(id: 1, workspace: first.workspace(for: side))
            let b = TestWindow.new(id: 1, workspace: second.mainWorkspace)
            _ = a.focusWindow()
            #expect(first.focus.windowOrNil === a)
            #expect(second.focus.windowOrNil === b)
            #expect(first.window(for: 1) === a)
            #expect(second.window(for: 1) === b)
            first.reconcileMonitors([main])
            #expect(first.workspaces.count == 1 && second.workspaces.count == 2)
        }

        @Test func popupAndMinimizedWindowsStayOutsideTilingTree() {
            let state = DisplayLayoutState(monitors: [main], pointer: TestPointerAdapter())
            let popup = TestWindow.new(id: 1, workspace: state.mainWorkspace, kind: .popup)
            let minimized = TestWindow.new(id: 2, workspace: state.mainWorkspace, kind: .minimized)
            #expect(state.window(for: 1) === popup && state.window(for: 2) === minimized)
            #expect(state.mainWorkspace.layout.windowIds.isEmpty)
            #expect(state.focus.windowOrNil == nil)
            #expect(DisplayLayoutState.shared.allWindows.isEmpty)
        }

        @Test func returningWindowsRestoreExactTreeRatiosAndDisplayInReverseOrder() {
            let state = DisplayLayoutState(monitors: [main, side], pointer: TestPointerAdapter())
            let workspace = state.workspace(for: side)
            let a = TestWindow.new(id: 1, workspace: workspace)
            let b = TestWindow.new(id: 2, workspace: workspace)
            let c = TestWindow.new(id: 3, workspace: workspace)
            workspace.layout.resize(1, by: 120, in: workspace.layoutRect, gap: 8)
            let original = workspace.layout
            state.removeWindow(a, remember: true)
            state.removeWindow(b, remember: true)
            state.removeWindow(c, remember: true)
            for id: UInt32 in [3, 2, 1] {
                let returned = TestWindow.new(id: id, workspace: state.mainWorkspace)
                #expect(state.restoreWindow(newlyDetectedWindow: returned))
                #expect(returned.workspace === workspace)
            }
            #expect(workspace.layout == original)
            #expect(state.mainWorkspace.isEffectivelyEmpty)
        }

        @Test func restorationRetainsNewWindowsAndFloatingMembership() {
            let state = DisplayLayoutState(monitors: [main, side], pointer: TestPointerAdapter())
            let a = TestWindow.new(id: 1, workspace: state.workspace(for: side))
            let floating = TestWindow.new(id: 2, workspace: state.workspace(for: side), kind: .floating)
            state.removeWindow(a, remember: true)
            state.removeWindow(floating, remember: true)
            let newcomer = TestWindow.new(id: 3, workspace: state.workspace(for: side))
            let returned = TestWindow.new(id: 2, workspace: state.mainWorkspace)
            #expect(state.restoreWindow(newlyDetectedWindow: returned))
            #expect(returned.kind == .floating && returned.workspace === state.workspace(for: side))
            #expect(newcomer.workspace?.layout.windowIds.contains(3) == true)
        }

        @Test func restorationIsInvalidatedBeforeAndAfterSuspendingMutation() async {
            let state = DisplayLayoutState(monitors: [main, side], pointer: TestPointerAdapter())
            let old = TestWindow.new(id: 1, workspace: state.workspace(for: side))
            state.removeWindow(old, remember: true)
            await state.changeLayout {
                await Task.yield()
                let returned = TestWindow.new(id: 1, workspace: state.mainWorkspace)
                #expect(!state.restoreWindow(newlyDetectedWindow: returned))
                state.removeWindow(returned, remember: true)
            }
            let returned = TestWindow.new(id: 1, workspace: state.mainWorkspace)
            #expect(!state.restoreWindow(newlyDetectedWindow: returned))
        }

        @Test func disconnectInvalidatesSnapshotButEmptyMonitorSnapshotDoesNot() {
            let state = DisplayLayoutState(monitors: [main, side], pointer: TestPointerAdapter())
            let old = TestWindow.new(id: 1, workspace: state.workspace(for: side))
            state.removeWindow(old, remember: true)
            state.reconcileMonitors([])
            let returned = TestWindow.new(id: 1, workspace: state.mainWorkspace)
            #expect(state.restoreWindow(newlyDetectedWindow: returned))
            state.removeWindow(returned, remember: true)
            state.reconcileMonitors([main])
            let afterDisconnect = TestWindow.new(id: 1, workspace: state.mainWorkspace)
            #expect(!state.restoreWindow(newlyDetectedWindow: afterDisconnect))
        }

        @Test func nativeStatesLeaveTreeAndReturnToOriginalDisplayAndKind() async {
            let state = DisplayLayoutState.shared
            let side = state.workspace(for: side)
            let window = TestWindow.new(id: 1, workspace: side, kind: .floating)
            let execution = ActionExecution(desktop: TestDesktopSessionAdapter())
            // Keep injected monitors in sync with the second display.
            unsafe testMonitors = [mainMonitorInfo, side.workspaceMonitor]
            TestApp.shared.isHidden = true
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(window.kind == .hidden)
            TestApp.shared.isHidden = false
            window.isMacosMinimizedForTest = true
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(window.kind == .minimized && window.workspace === side)
            window.isMacosMinimizedForTest = false
            window.isMacosFullscreenForTest = true
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(window.kind == .nativeFullscreen)
            window.isMacosFullscreenForTest = false
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(window.kind == .floating && window.workspace === side)
            #expect(side.layout.windowIds.isEmpty)
            state.place(window, on: side, kind: .tiled)
            window.isMacosMinimizedForTest = true
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(side.layout.windowIds.isEmpty)
            window.isMacosMinimizedForTest = false
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(side.layout.windowIds == [1])
        }
    }
}
