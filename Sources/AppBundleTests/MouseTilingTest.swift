import AppKit
import Testing

@testable import AppBundle

extension CoreTests {
    @MainActor struct MouseTilingTest {
        init() { setUpWorkspacesForTests() }

        @Test func centerDropSwapsAndEdgeDropReinserts() throws {
            let workspace = focus.workspace
            let a = TestWindow.new(id: 1, workspace: workspace)
            TestWindow.new(id: 2, workspace: workspace)
            let frames = workspace.tiledFrames
            let first = try #require(frames[1])
            let second = try #require(frames[2])
            let mouse = MouseTiling()
            mouse.observe(a, frame: first, resizing: false)
            mouse.finish(at: second.center, on: workspace)
            #expect(workspace.tiledFrames[1]?.topLeftCorner == second.topLeftCorner)
            let target = try #require(workspace.tiledFrames[2])
            mouse.observe(a, frame: second, resizing: false)
            mouse.finish(at: CGPoint(x: target.center.x, y: target.maxY - 1), on: workspace)
            #expect(workspace.tiledFrames[1]!.minY > workspace.tiledFrames[2]!.maxY)
            #expect(Set(workspace.layout.windowIds) == Set([1, 2]))
            #expect(currentlyManipulatedWithMouseWindowId == nil)
        }

        @Test func dragRearrangesBeforeReleaseAndDoesNotRepeatAtSameTarget() throws {
            let workspace = focus.workspace
            let a = TestWindow.new(id: 1, workspace: workspace)
            TestWindow.new(id: 2, workspace: workspace)
            let frame = try #require(workspace.tiledFrames[1])
            let target = try #require(workspace.tiledFrames[2])
            let mouse = MouseTiling()
            mouse.observe(a, frame: frame, resizing: false)
            mouse.drag(at: target.center, on: workspace)
            #expect(workspace.tiledFrames[1]?.topLeftCorner == target.topLeftCorner)
            #expect(currentlyManipulatedWithMouseWindowId == 1)
            let swapped = workspace.layout
            mouse.observe(a, frame: frame, resizing: false)
            mouse.drag(at: target.center, on: workspace)
            #expect(workspace.layout == swapped)

            // Leaving the previous target permits another live edit in the same gesture.
            let next = try #require(workspace.tiledFrames[2])
            let edge = CGPoint(x: next.center.x, y: next.maxY - 1)
            mouse.drag(at: edge, on: workspace)
            #expect(workspace.tiledFrames[1]!.minY > workspace.tiledFrames[2]!.maxY)
            let inserted = workspace.layout
            mouse.drag(at: edge, on: workspace)
            mouse.finish(at: edge, on: workspace)
            #expect(workspace.layout == inserted)
            #expect(currentlyManipulatedWithMouseWindowId == nil)
        }

        @Test func dragAcrossDisplaysAndBackContinuesBeforeRelease() throws {
            let source = focus.workspace
            let side = TestMonitor(displayId: "side", name: "Side", x: 1920)
            unsafe testMonitors = monitorInfos + [side]
            DisplayLayoutState.shared.reconcileMonitors(monitorInfos)
            let destination = side.activeWorkspace
            let a = TestWindow.new(id: 1, workspace: source)
            TestWindow.new(id: 2, workspace: destination)
            let original = try #require(source.tiledFrames[1])
            let target = try #require(destination.tiledFrames[2])
            let mouse = MouseTiling()
            mouse.observe(a, frame: original, resizing: false)
            mouse.drag(at: target.center, on: destination)
            #expect(source.layout.windowIds.isEmpty)
            #expect(a.workspace === destination)
            #expect(Set(destination.layout.windowIds) == Set([1, 2]))
            #expect(focus.windowOrNil === a && focus.workspace === destination)
            let transferred = destination.layout
            mouse.observe(a, frame: original, resizing: false)
            mouse.drag(at: target.center, on: destination)
            #expect(destination.layout == transferred)
            #expect(currentlyManipulatedWithMouseWindowId == 1)
            mouse.drag(at: source.layoutRect.center, on: source)
            #expect(a.workspace === source)
            #expect(source.layout.windowIds == [1])
            #expect(destination.layout.windowIds == [2])
            mouse.finish(at: source.layoutRect.center, on: source)
            #expect(focus.windowOrNil === a && focus.workspace === source)
        }

        @Test func dragSessionAppliesNeighborFramesWhileDraggedWindowStaysUnderMouse() async throws {
            let workspace = focus.workspace
            let a = TestWindow.new(id: 1, workspace: workspace)
            let b = TestWindow.new(id: 2, workspace: workspace)
            try await workspace.layoutWorkspace()
            let first = try #require(await a.getAxRect(.nonCancellable))
            let second = try #require(await b.getAxRect(.nonCancellable))
            let desktop = TestDesktopSessionAdapter()
            desktop.nativeFocus = a
            let execution = ActionExecution(desktop: desktop)
            let mouse = MouseTiling()
            defer {
                execution.cancelRefresh()
                mouse.cancel()
            }
            try await execution.runSession(.ax("AXMoved"), .forceRun) {
                await DisplayLayoutState.shared.changeLayout {
                    mouse.observe(a, frame: first, resizing: false)
                    mouse.drag(at: second.center, on: workspace)
                }
            }
            let dragged = try #require(await a.getAxRect(.nonCancellable))
            let neighbor = try #require(await b.getAxRect(.nonCancellable))
            #expect(dragged.topLeftCorner == first.topLeftCorner)
            #expect(neighbor.topLeftCorner == first.topLeftCorner)
            #expect(currentlyManipulatedWithMouseWindowId == 1)
            mouse.finish(at: second.center, on: workspace)
            try await workspace.layoutWorkspace()
            let released = try #require(await a.getAxRect(.nonCancellable))
            #expect(released.topLeftCorner == second.topLeftCorner)
        }

        @Test func liveDragRejectsExternalLayoutChanges() throws {
            let workspace = focus.workspace
            let a = TestWindow.new(id: 1, workspace: workspace)
            TestWindow.new(id: 2, workspace: workspace)
            let mouse = MouseTiling()
            mouse.observe(a, frame: try #require(workspace.tiledFrames[1]), resizing: false)
            workspace.layout.toggleSplit(for: 2, in: workspace.layoutRect, gap: 8)
            let changed = workspace.layout
            mouse.drag(at: workspace.tiledFrames[2]!.center, on: workspace)
            #expect(workspace.layout == changed)
            #expect(currentlyManipulatedWithMouseWindowId == nil)
        }

        @Test func resizeUsesAbsoluteGestureDeltaAndPromotesCorrectDivider() throws {
            let workspace = focus.workspace
            let a = TestWindow.new(id: 1, workspace: workspace)
            TestWindow.new(id: 2, workspace: workspace)
            let original = try #require(workspace.tiledFrames[1])
            let mouse = MouseTiling()
            var resized = original
            resized.width += 40
            mouse.observe(a, frame: resized, resizing: true)
            #expect(abs(workspace.tiledFrames[1]!.width - original.width - 40) < 0.001)
            resized.width += 30
            mouse.observe(a, frame: resized, resizing: true)
            #expect(abs(workspace.tiledFrames[1]!.width - original.width - 70) < 0.001)
            let layout = workspace.layout
            mouse.drag(at: workspace.tiledFrames[2]!.center, on: workspace)
            #expect(workspace.layout == layout)
            mouse.finish(at: resized.center, on: workspace)
            #expect(workspace.layout.windowIds == [1, 2])
        }

        @Test func crossMonitorDropAndEmptyDestination() throws {
            let source = focus.workspace
            let side = TestMonitor(displayId: "side", name: "Side", x: 1920)
            unsafe testMonitors = monitorInfos + [side]
            DisplayLayoutState.shared.reconcileMonitors(monitorInfos)
            let destination = side.activeWorkspace
            let window = TestWindow.new(id: 1, workspace: source)
            let mouse = MouseTiling()
            mouse.observe(window, frame: try #require(source.tiledFrames[1]), resizing: false)
            mouse.finish(at: destination.layoutRect.center, on: destination)
            #expect(source.layout.windowIds.isEmpty)
            #expect(destination.layout.windowIds == [1])
            #expect(focus.windowOrNil === window && focus.workspace === destination)
        }

        @Test func crossMonitorDropIntoPopulatedTreeSplitsTarget() throws {
            let source = focus.workspace
            let side = TestMonitor(displayId: "side", name: "Side", x: 1920)
            unsafe testMonitors = monitorInfos + [side]
            DisplayLayoutState.shared.reconcileMonitors(monitorInfos)
            let destination = side.activeWorkspace
            let a = TestWindow.new(id: 1, workspace: source)
            TestWindow.new(id: 2, workspace: destination)
            let target = try #require(destination.tiledFrames[2])
            let mouse = MouseTiling()
            mouse.observe(a, frame: try #require(source.tiledFrames[1]), resizing: false)
            mouse.finish(at: CGPoint(x: target.minX + 1, y: target.center.y), on: destination)
            #expect(source.layout.windowIds.isEmpty)
            #expect(destination.layout.windowIds == [1, 2])
            #expect(a.workspace === destination)
        }

        @Test func displayGeometryChangeInvalidatesPendingDrop() throws {
            let workspace = focus.workspace
            let a = TestWindow.new(id: 1, workspace: workspace)
            TestWindow.new(id: 2, workspace: workspace)
            let mouse = MouseTiling()
            mouse.observe(a, frame: try #require(workspace.tiledFrames[1]), resizing: false)
            let before = workspace.layout
            workspace.workspaceMonitor = TestMonitor(displayId: workspace.name, name: "Moved", x: 100)
            mouse.finish(at: workspace.tiledFrames[2]!.center, on: workspace)
            #expect(workspace.layout == before)
            #expect(currentlyManipulatedWithMouseWindowId == nil)
        }

        @Test func staleGestureCannotOverwriteKeyboardEditOrResurrectClosedWindow() throws {
            let workspace = focus.workspace
            let a = TestWindow.new(id: 1, workspace: workspace)
            TestWindow.new(id: 2, workspace: workspace)
            let frame = try #require(workspace.tiledFrames[1])
            let mouse = MouseTiling()
            mouse.observe(a, frame: frame, resizing: false)
            workspace.layout.toggleSplit(for: 2, in: workspace.layoutRect, gap: 8)
            let changed = workspace.layout
            mouse.finish(at: workspace.tiledFrames[2]!.center, on: workspace)
            #expect(workspace.layout == changed)
            mouse.observe(a, frame: frame, resizing: false)
            workspace.state.removeWindow(a, remember: false)
            mouse.finish(at: workspace.layoutRect.center, on: workspace)
            #expect(workspace.layout.windowIds == [2])
        }
    }
}
