import AppKit
import Testing

@testable import AppBundle

extension CoreTests {
    @MainActor struct TilingPolicyTest {
        init() { setUpWorkspacesForTests() }

        @Test func closeRestoresRecentFloatAndFloatingFocusKeepsTiledInsertionTarget() {
            let workspace = focus.workspace
            let a = TestWindow.new(id: 1, workspace: workspace)
            let b = TestWindow.new(id: 2, workspace: workspace)
            let floating = TestWindow.new(id: 3, workspace: workspace, kind: .floating)
            _ = a.focusWindow()
            _ = floating.focusWindow()
            #expect(workspace.insertionTarget == 1)
            _ = b.focusWindow()
            let replacement = workspace.state.removeWindow(b, remember: false)
            #expect(replacement === floating && focus.windowOrNil === floating)
            #expect(workspace.insertionTarget == 1)
        }

        @Test func failedInsertionFloatsOnlyArrivalAndExplicitRetileUsesPlacement() {
            let workspace = focus.workspace
            let a = TestWindow.new(id: 1, workspace: workspace)
            TestWindow.new(id: 2, workspace: workspace)
            let arriving = TestWindow.new(id: 3, workspace: workspace, kind: .floating)
            arriving.minimumSize = CGSize(width: 1200, height: 900)
            let before = workspace.layout
            workspace.state.place(arriving, on: workspace, kind: .tiled)
            #expect(arriving.kind == .floating && workspace.layout == before)
            arriving.minimumSize = BinaryLayout.baseline
            _ = a.focusWindow()
            ConfigurationApplication.shared.apply("new-window-placement = 'inner'")
            workspace.state.place(arriving, on: workspace, kind: .tiled)
            #expect(arriving.kind == .tiled)
            #expect(workspace.tiledFrames[3]!.maxY < workspace.tiledFrames[1]!.minY)
        }

        @Test func screenShrinkFloatsLeastRecentAndDoesNotAutomaticallyRetileLater() {
            let workspace = focus.workspace
            let a = TestWindow.new(id: 1, workspace: workspace)
            let b = TestWindow.new(id: 2, workspace: workspace)
            let c = TestWindow.new(id: 3, workspace: workspace)
            _ = b.focusWindow()
            _ = c.focusWindow()
            _ = a.focusWindow()
            let small = TestMonitor(displayId: workspace.name, name: "Small", x: 0, width: 680, height: 400)
            workspace.state.reconcileMonitors([small])
            #expect(b.kind == .floating)
            #expect(a.kind == .tiled && c.kind == .tiled)
            #expect(workspace.layout.isValid(in: workspace.layoutRect, gap: 8))
            workspace.state.reconcileMonitors([TestMonitor(displayId: workspace.name, name: "Big", x: 0)])
            #expect(b.kind == .floating)
        }

        @Test func disconnectPrefersRecentSurvivorAndKeepsSuspendedWindowAssigned() {
            let state = DisplayLayoutState.shared
            let main = focus.workspace
            let side = state.workspace(for: TestMonitor(displayId: "side", name: "Side", x: 1920))
            let third = state.workspace(for: TestMonitor(displayId: "third", name: "Third", x: 3840))
            let a = TestWindow.new(id: 1, workspace: side)
            let b = TestWindow.new(id: 2, workspace: third)
            let minimized = TestWindow.new(id: 3, workspace: third, kind: .minimized)
            _ = a.focusWindow()
            _ = b.focusWindow()
            state.reconcileMonitors([main.workspaceMonitor, side.workspaceMonitor])
            #expect(b.workspace === side && minimized.workspace === side)
            #expect(focus.windowOrNil === b && main.layout.windowIds.isEmpty)
            state.place(minimized, on: side, kind: .tiled)
            #expect(minimized.workspace === side && minimized.kind == .tiled)
        }

        @Test func migrationUsesOriginalKindEvenWhenSourceCollapseWouldViolateMinimum() {
            let state = DisplayLayoutState.shared
            let destination = focus.workspace
            let source = state.workspace(
                for: TestMonitor(displayId: "side", name: "Side", x: 1920, width: 680, height: 1080))
            source.orientationOverride = .h
            source.recover()
            let a = TestWindow.new(id: 1, workspace: source)
            let b = TestWindow.new(id: 2, workspace: source)
            let c = TestWindow.new(id: 3, workspace: source)
            _ = c.focusWindow()
            state.reconcileMonitors([destination.workspaceMonitor])
            #expect([a, b, c].allSatisfy { $0.workspace === destination && $0.kind == .tiled })
            #expect(Set(destination.layout.windowIds) == [1, 2, 3])
        }

        @Test func directionalFocusSkipsEmptyScreensAndCanStartOnOne() async {
            let first = focus.workspace
            let middle = TestMonitor(displayId: "middle", name: "Middle", x: 1920)
            let last = TestMonitor(displayId: "last", name: "Last", x: 3840)
            unsafe testMonitors = [first.workspaceMonitor, middle, last]
            first.state.reconcileMonitors(monitorInfos)
            let a = TestWindow.new(id: 1, workspace: first)
            let b = TestWindow.new(id: 2, workspace: last.activeWorkspace)
            _ = a.focusWindow()
            await Action.focusRight.applyToModel()
            #expect(focus.windowOrNil === b)
            await Action.focusRight.applyToModel()
            #expect(focus.windowOrNil === b)
            _ = middle.activeWorkspace.focusWorkspace()
            await Action.focusLeft.applyToModel()
            #expect(focus.windowOrNil === a)
        }

        @Test func explicitRootOrientationAndPerScreenFlipSurviveGeometryChange() async {
            ConfigurationApplication.shared.apply("root-orientation = 'vertical'")
            let workspace = focus.workspace
            workspace.recover()
            let a = TestWindow.new(id: 1, workspace: workspace)
            TestWindow.new(id: 2, workspace: workspace)
            #expect(workspace.tiledFrames[1]?.width == workspace.layoutRect.width)
            _ = a.focusWindow()
            await Action.toggleOrientation.applyToModel()
            #expect(workspace.layout.rootAxis == .h)
            workspace.state.reconcileMonitors([
                TestMonitor(displayId: workspace.name, name: "Portrait", x: 0, width: 1000, height: 1600)
            ])
            #expect(workspace.layout.rootAxis == .h)
            #expect(workspace.layout.isValid(in: workspace.layoutRect, gap: 8))
        }

        @Test func observedNativeLimitsIgnoreStaleAndTransientFrames() {
            let workspace = focus.workspace
            let window = TestWindow.new(id: 1, workspace: workspace)
            let request = Rect(topLeftX: 0, topLeftY: 0, width: 400, height: 300)
            window.lastAppliedLayoutPhysicalRect = request
            let snapped = CGSize(width: 412, height: 316)
            #expect(!window.observeSizeConstraint(requested: request.size, actual: snapped))
            #expect(!window.observeSizeConstraint(requested: request.size, actual: snapped))
            #expect(window.minimumSize == BinaryLayout.baseline)
            let actual = CGSize(width: 600, height: 350)
            #expect(!window.observeSizeConstraint(requested: request.size, actual: actual))
            #expect(window.minimumSize == BinaryLayout.baseline)
            #expect(window.observeSizeConstraint(requested: request.size, actual: actual))
            #expect(window.minimumSize == actual)
            #expect(
                !window.observeSizeConstraint(
                    requested: CGSize(width: 320, height: 200), actual: CGSize(width: 900, height: 800)))
            window.kind = .floating
            #expect(!window.observeSizeConstraint(requested: request.size, actual: actual))
            #expect(window.minimumSize == actual)
        }

        @Test func returningNativeFocusedWindowReclaimsLogicalFocus() async {
            let workspace = focus.workspace
            let a = TestWindow.new(id: 1, workspace: workspace)
            let b = TestWindow.new(id: 2, workspace: workspace)
            _ = b.focusWindow()
            _ = a.focusWindow()
            let desktop = TestDesktopSessionAdapter()
            desktop.nativeFocus = a
            let execution = ActionExecution(desktop: desktop)
            a.isMacosMinimizedForTest = true
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(a.kind == .minimized && focus.windowOrNil === b)
            a.isMacosMinimizedForTest = false
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(a.kind == .tiled && focus.windowOrNil === a)
        }

        @Test func nonResizableWindowCannotBeRetiled() {
            let workspace = focus.workspace
            let window = TestWindow.new(id: 1, workspace: workspace, kind: .floating)
            window.isResizable = false
            workspace.state.place(window, on: workspace, kind: .tiled)
            #expect(window.kind == .floating && workspace.layout.windowIds.isEmpty)
        }
    }
}
