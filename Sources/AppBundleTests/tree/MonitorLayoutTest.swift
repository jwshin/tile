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
            DisplayLayoutState.shared.reconcileMonitors(monitors)
        }

        @Test func initialRootFollowsUsableScreenShape() {
            let portrait = TestMonitor(displayId: "portrait", name: "Portrait", x: 1920, width: 1080, height: 1920)
            connect([main, portrait])
            for (monitor, base) in [(main, UInt32(1)), (portrait, UInt32(3))] {
                TestWindow.new(id: base, workspace: monitor.activeWorkspace)
                TestWindow.new(id: base + 1, workspace: monitor.activeWorkspace)
            }
            #expect(main.activeWorkspace.tiledFrames[1]?.height == main.activeWorkspace.layoutRect.height)
            #expect(portrait.activeWorkspace.tiledFrames[3]?.width == portrait.activeWorkspace.layoutRect.width)
        }

        @Test func onePermanentLayoutPerMonitor() {
            connect([main, side])
            let first = main.activeWorkspace
            let second = side.activeWorkspace
            #expect(first !== second)
            #expect(DisplayLayoutState.shared.workspaces.count == 2)
            let allVisible = DisplayLayoutState.shared.workspaces.allSatisfy { $0.isVisible }
            #expect(allVisible)
            _ = second.focusWorkspace()
            _ = first.focusWorkspace()
            #expect(side.activeWorkspace === second)
            #expect(main.activeWorkspace === first)
            #expect(DisplayLayoutState.shared.workspaces.count == 2)
        }

        @Test func rearrangingDisplaysPreservesTheirTrees() {
            connect([main, side])
            let original = side.activeWorkspace
            let window = TestWindow.new(id: 1, workspace: original)
            let moved = TestMonitor(displayId: "side", name: "Side", x: -1920)
            connect([main, moved])
            #expect(moved.activeWorkspace === original)
            #expect(window.workspace === original)
            #expect(original.workspaceMonitor.rect.minX == -1920)
        }

        @Test func disconnectInsertsIndividuallyAndReconnectStartsEmpty() {
            connect([main, side])
            let destination = main.activeWorkspace
            TestWindow.new(id: 1, workspace: destination)
            TestWindow.new(id: 2, workspace: destination)
            let source = side.activeWorkspace
            let a = TestWindow.new(id: 3, workspace: source)
            let b = TestWindow.new(id: 4, workspace: source)
            source.flipOrientation()
            source.layout.resize(3, by: 100, in: source.layoutRect, gap: 8)
            let floating = TestWindow.new(id: 5, workspace: source, kind: .floating)
            let fullscreen = TestWindow.new(id: 6, workspace: source, kind: .nativeFullscreen)
            let minimized = TestWindow.new(id: 7, workspace: source, kind: .minimized)
            var expected = destination.layout
            expected.insert(3, beside: destination.insertionTarget, in: destination.layoutRect, gap: 8)
            expected.insert(4, beside: 3, in: destination.layoutRect, gap: 8)
            _ = b.focusWindow()
            connect([main])
            #expect(destination.layout == expected)
            for window in [a, b, floating, fullscreen, minimized] { #expect(window.workspace === destination) }
            #expect(focus.windowOrNil === b)
            connect([main, side])
            #expect(side.activeWorkspace !== source && side.activeWorkspace.isEffectivelyEmpty)
            #expect(destination.layout == expected)
        }

        @Test func noScreensDuringReconfigurationDoesNotDiscardLayouts() {
            connect([main, side])
            let window = TestWindow.new(id: 1, workspace: side.activeWorkspace)
            connect([])
            #expect(DisplayLayoutState.shared.workspaces.count == 2)
            #expect(window.isRegistered)
            connect([main, side])
            #expect(window.workspace === side.activeWorkspace)
        }

        @Test func monitorCommandsMoveAndFocusWithoutCreatingWorkspaces() async {
            connect([main, side])
            let window = TestWindow.new(id: 1, workspace: main.activeWorkspace)
            _ = window.focusWindow()
            let move = await Action.moveToMonitorRight.applyToModel()
            #expect(move.exitCode.rawValue == 0)
            #expect(window.workspace === side.activeWorkspace)
            #expect(focus.windowOrNil === window)
            let focusResult = await Action.leftMonitor.applyToModel()
            #expect(focusResult.exitCode.rawValue == 0)
            #expect(focus.workspace === main.activeWorkspace)
            #expect(DisplayLayoutState.shared.workspaces.count == 2)
        }

        @Test func monitorCyclingWrapsAndMovingAlwaysFollowsWindow() async {
            connect([main, side])
            let window = TestWindow.new(id: 1, workspace: main.activeWorkspace)
            _ = window.focusWindow()
            await Action.previousMonitor.applyToModel()
            #expect(focus.workspace === side.activeWorkspace)
            await Action.nextMonitor.applyToModel()
            #expect(focus.windowOrNil === window)
            await Action.moveToPreviousMonitor.applyToModel()
            #expect(window.workspace === side.activeWorkspace)
            #expect(focus.windowOrNil === window)
            await Action.moveToNextMonitor.applyToModel()
            #expect(window.workspace === main.activeWorkspace)
            #expect(focus.windowOrNil === window)
        }

        @Test func directionalFocusCrossesScreensWithoutWrapping() async {
            connect([main, side])
            let first = TestWindow.new(id: 1, workspace: main.activeWorkspace)
            let last = TestWindow.new(id: 2, workspace: main.activeWorkspace)
            TestWindow.new(id: 3, workspace: side.activeWorkspace)
            _ = last.focusWindow()
            await Action.focusRight.applyToModel()
            #expect(focus.windowOrNil?.windowId == 3)
            _ = first.focusWindow()
            await Action.focusLeft.applyToModel()
            #expect(focus.windowOrNil === first)
            let result = await Action.leftMonitor.applyToModel()
            #expect(result.exitCode == .fail)
            #expect(focus.workspace === main.activeWorkspace)
        }

        @Test func cyclingOneMonitorLeavesLayoutAndFocusIntact() async {
            connect([main])
            let workspace = main.activeWorkspace
            let a = TestWindow.new(id: 1, workspace: workspace)
            TestWindow.new(id: 2, workspace: workspace)
            workspace.layout.resize(1, by: 100, in: workspace.layoutRect, gap: 8)
            let original = workspace.layout
            _ = a.focusWindow()
            for action in [Action.nextMonitor, .previousMonitor, .moveToNextMonitor, .moveToPreviousMonitor] {
                let result = await action.applyToModel()
                #expect(result.exitCode == .succ)
                #expect(workspace.layout == original)
                #expect(focus.windowOrNil === a)
            }
        }

        @Test func uniformGapAppliesToEveryDisplayAndFullscreen() async throws {
            connect([main, side])
            ConfigurationApplication.shared.apply("gap = 12")
            for monitor in [main, side] {
                let workspace = monitor.activeWorkspace
                let a = TestWindow.new(id: monitor.isMain ? 1 : 3, workspace: workspace)
                let b = TestWindow.new(id: monitor.isMain ? 2 : 4, workspace: workspace)
                try await workspace.layoutWorkspace()
                let first = try #require(await a.getAxRect(.nonCancellable))
                let second = try #require(await b.getAxRect(.nonCancellable))
                #expect(first.minX == monitor.rect.minX + 12)
                #expect(first.minY == monitor.rect.minY + 12)
                #expect(second.minX - first.maxX == 12)
                #expect(second.maxX == monitor.rect.maxX - 12)
                _ = a.focusWindow()
                await Action.fullscreen.applyToModel()
                try await workspace.layoutWorkspace()
                let fullscreen = try #require(await a.getAxRect(.nonCancellable))
                let expected = monitor.visibleRectPaddedByOuterGaps
                #expect(fullscreen.topLeftCorner == expected.topLeftCorner)
                #expect(fullscreen.size == expected.size)
                await Action.fullscreen.applyToModel()
                #expect(!a.isFullscreen)
            }
        }

        @Test func disconnectedFloatingWindowIsBroughtOnScreen() async throws {
            connect([main, side])
            let window = TestWindow.new(
                id: 1, workspace: side.activeWorkspace, kind: .floating,
                rect: Rect(topLeftX: 2200, topLeftY: 100, width: 400, height: 300))
            connect([main])
            try await main.activeWorkspace.layoutWorkspace()
            let rect = try #require(await window.getAxRect(.nonCancellable))
            #expect(rect.minX >= main.visibleRect.minX)
            #expect(rect.maxX <= main.visibleRect.maxX)
        }

    }
}
