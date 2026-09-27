import AppKit
import Common
import Testing

@testable import AppBundle

extension CoreTests {
    @MainActor struct MonitorLayoutTest {
        init() { setUpWorkspacesForTests() }

        private let main = TestMonitor(displayId: "test-main", name: "Main", x: 0, isMain: true)
        private let side = TestMonitor(displayId: "side", name: "Side", x: 1920)

        private func connect(_ monitors: [MonitorInfo]) {
            unsafe testMonitors = monitors
            Workspace.reconcileMonitors(monitors)
        }

        @Test func newLayoutsFollowDisplayAspectRatio() {
            let portrait = TestMonitor(displayId: "portrait", name: "Portrait", x: 1920, width: 1080, height: 1920)
            let square = TestMonitor(displayId: "square", name: "Square", x: 3000, width: 1200, height: 1200)
            connect([main, portrait, square])
            #expect(main.activeWorkspace.rootTilingContainer.orientation == .h)
            #expect(portrait.activeWorkspace.rootTilingContainer.orientation == .v)
            #expect(square.activeWorkspace.rootTilingContainer.orientation == .h)
        }

        @Test func onePermanentLayoutPerMonitor() {
            connect([main, side])
            let first = main.activeWorkspace
            let second = side.activeWorkspace
            #expect(first !== second)
            #expect(Workspace.all.count == 2)
            let allVisible = Workspace.all.allSatisfy { $0.isVisible }
            #expect(allVisible)
            _ = second.focusWorkspace()
            _ = first.focusWorkspace()
            #expect(side.activeWorkspace === second)
            #expect(main.activeWorkspace === first)
            #expect(Workspace.all.count == 2)
        }

        @Test func rearrangingDisplaysPreservesTheirTrees() {
            connect([main, side])
            let original = side.activeWorkspace
            let window = TestWindow.new(id: 1, parent: original.rootTilingContainer)
            let moved = TestMonitor(displayId: "side", name: "Side", x: -1920)
            connect([main, moved])
            #expect(moved.activeWorkspace === original)
            #expect(window.nodeWorkspace === original)
            #expect(original.workspaceMonitor.rect.minX == -1920)
        }

        @Test func disconnectMergesSubtreeAndReconnectStartsEmpty() {
            connect([main, side])
            let source = side.activeWorkspace
            let root = source.rootTilingContainer
            root.changeOrientation(.v)
            let a = TestWindow.new(id: 1, parent: root, adaptiveWeight: 3)
            let b = TestWindow.new(id: 2, parent: root, adaptiveWeight: 1)
            let floating = TestWindow.new(id: 3, parent: source.floatingWindowsContainer)
            let nativeFullscreen = TestWindow.new(id: 4, parent: source.macOsNativeFullscreenWindowsContainer)
            let hidden = TestWindow.new(id: 5, parent: source.macOsNativeHiddenAppsWindowsContainer)
            _ = b.focusWindow()
            connect([main])
            #expect(Workspace.all.count == 1)
            #expect(root === main.activeWorkspace.rootTilingContainer)
            #expect(root.children == [a, b])
            #expect(root.orientation == .v)
            #expect(a.vWeight == 3 && b.vWeight == 1)
            #expect(floating.nodeWorkspace === main.activeWorkspace)
            #expect(nativeFullscreen.nodeWorkspace === main.activeWorkspace)
            #expect(hidden.nodeWorkspace === main.activeWorkspace)
            #expect(focus.windowOrNil === b)
            connect([main, side])
            #expect(side.activeWorkspace !== source)
            #expect(side.activeWorkspace.isEffectivelyEmpty)
            #expect(a.nodeWorkspace === main.activeWorkspace)
        }

        @Test func mergingPopulatedDisplaysSurvivesNormalization() {
            connect([main, side])
            let a = TestWindow.new(id: 1, parent: main.activeWorkspace.rootTilingContainer)
            let b = TestWindow.new(id: 2, parent: main.activeWorkspace.rootTilingContainer)
            let c = TestWindow.new(id: 3, parent: side.activeWorkspace.rootTilingContainer)
            let d = TestWindow.new(id: 4, parent: side.activeWorkspace.rootTilingContainer)
            connect([main])
            main.activeWorkspace.normalizeContainers()
            #expect(a.parent === b.parent)
            #expect(c.parent === d.parent)
            #expect((a.parent as? TilingContainer)?.orientation == .h)
            #expect((c.parent as? TilingContainer)?.orientation == .h)
            #expect(main.activeWorkspace.rootTilingContainer.orientation == .v)
        }

        @Test func noScreensDuringReconfigurationDoesNotDiscardLayouts() {
            connect([main, side])
            let window = TestWindow.new(id: 1, parent: side.activeWorkspace.rootTilingContainer)
            connect([])
            #expect(Workspace.all.count == 2)
            #expect(window.parent != nil)
            connect([main, side])
            #expect(window.nodeWorkspace === side.activeWorkspace)
        }

        @Test func monitorCommandsMoveAndFocusWithoutCreatingWorkspaces() async {
            connect([main, side])
            let window = TestWindow.new(id: 1, parent: main.activeWorkspace.rootTilingContainer)
            _ = window.focusWindow()
            let move = await Action.moveToMonitorRight.run()
            #expect(move.exitCode.rawValue == 0)
            #expect(window.nodeWorkspace === side.activeWorkspace)
            #expect(focus.windowOrNil === window)
            let focusResult = await Action.leftMonitor.run()
            #expect(focusResult.exitCode.rawValue == 0)
            #expect(focus.workspace === main.activeWorkspace)
            #expect(Workspace.all.count == 2)
        }

        @Test func monitorCyclingWrapsAndMovingAlwaysFollowsWindow() async {
            connect([main, side])
            let window = TestWindow.new(id: 1, parent: main.activeWorkspace.rootTilingContainer)
            _ = window.focusWindow()
            await Action.previousMonitor.run()
            #expect(focus.workspace === side.activeWorkspace)
            await Action.nextMonitor.run()
            #expect(focus.windowOrNil === window)
            await Action.moveToPreviousMonitor.run()
            #expect(window.nodeWorkspace === side.activeWorkspace)
            #expect(focus.windowOrNil === window)
            await Action.moveToNextMonitor.run()
            #expect(window.nodeWorkspace === main.activeWorkspace)
            #expect(focus.windowOrNil === window)
        }

        @Test func directionalFocusStopsAtMonitorEdge() async {
            connect([main, side])
            let first = TestWindow.new(id: 1, parent: main.activeWorkspace.rootTilingContainer)
            let last = TestWindow.new(id: 2, parent: main.activeWorkspace.rootTilingContainer)
            TestWindow.new(id: 3, parent: side.activeWorkspace.rootTilingContainer)
            _ = last.focusWindow()
            await Action.focusRight.run()
            #expect(focus.windowOrNil === last)
            _ = first.focusWindow()
            await Action.focusLeft.run()
            #expect(focus.windowOrNil === first)
            let result = await Action.leftMonitor.run()
            #expect(result.exitCode == .fail)
            #expect(focus.workspace === main.activeWorkspace)
        }

        @Test func cyclingOneMonitorLeavesLayoutAndFocusIntact() async {
            connect([main])
            let root = main.activeWorkspace.rootTilingContainer
            let a = TestWindow.new(id: 1, parent: root, adaptiveWeight: 200)
            let b = TestWindow.new(id: 2, parent: root, adaptiveWeight: 100)
            _ = a.focusWindow()
            for action in [Action.nextMonitor, .previousMonitor, .moveToNextMonitor, .moveToPreviousMonitor] {
                let result = await action.run()
                #expect(result.exitCode == .succ)
                #expect(root.children == [a, b])
                #expect(focus.windowOrNil === a)
                #expect(a.hWeight == 200 && b.hWeight == 100)
            }
        }

        @Test func uniformGapAppliesToEveryDisplayAndFullscreen() async throws {
            connect([main, side])
            config.gap = 12
            for monitor in [main, side] {
                let workspace = monitor.activeWorkspace
                let a = TestWindow.new(id: monitor.isMain ? 1 : 3, parent: workspace.rootTilingContainer)
                let b = TestWindow.new(id: monitor.isMain ? 2 : 4, parent: workspace.rootTilingContainer)
                try await workspace.layoutWorkspace()
                let first = try #require(await a.getAxRect(.nonCancellable))
                let second = try #require(await b.getAxRect(.nonCancellable))
                #expect(first.minX == monitor.rect.minX + 12)
                #expect(first.minY == monitor.rect.minY + 12)
                #expect(second.minX - first.maxX == 12)
                #expect(second.maxX == monitor.rect.maxX - 12)
                _ = a.focusWindow()
                await Action.fullscreen.run()
                try await workspace.layoutWorkspace()
                let fullscreen = try #require(await a.getAxRect(.nonCancellable))
                let expected = monitor.visibleRectPaddedByOuterGaps
                #expect(fullscreen.topLeftCorner == expected.topLeftCorner)
                #expect(fullscreen.size == expected.size)
                await Action.fullscreen.run()
                #expect(!a.isFullscreen)
            }
        }

        @Test func disconnectedFloatingWindowIsBroughtOnScreen() async throws {
            connect([main, side])
            let window = TestWindow.new(
                id: 1, parent: side.activeWorkspace.floatingWindowsContainer,
                rect: Rect(topLeftX: 2200, topLeftY: 100, width: 400, height: 300))
            connect([main])
            try await main.activeWorkspace.layoutWorkspace()
            let rect = try #require(await window.getAxRect(.nonCancellable))
            #expect(rect.minX >= main.visibleRect.minX)
            #expect(rect.maxX <= main.visibleRect.maxX)
        }

        @Test func lockScreenRestorationKeepsDisplayMembership() async throws {
            connect([main, side])
            let root = side.activeWorkspace.rootTilingContainer
            root.changeOrientation(.v)
            let a = TestWindow.new(id: 1, parent: root)
            let b = TestWindow.new(id: 2, parent: root)
            cacheClosedWindowIfNeeded()
            a.unbindFromParent()
            b.unbindFromParent()
            a.bind(to: main.activeWorkspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
            b.bind(to: main.activeWorkspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
            #expect(try await restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: a))
            #expect(a.nodeWorkspace === side.activeWorkspace)
            #expect(b.nodeWorkspace === side.activeWorkspace)
            #expect(side.activeWorkspace.rootTilingContainer.orientation == .v)
        }
    }
}
