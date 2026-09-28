import AppKit
import Common
import Testing

@testable import AppBundle

extension CoreTests {
    @MainActor struct MouseTilingTest {
        init() { setUpWorkspacesForTests() }
        private func setupThree() -> (Workspace, TestWindow, TestWindow, TestWindow) {
            let workspace = focus.workspace
            let a = TestWindow.new(id: 1, workspace: workspace)
            let b = TestWindow.new(id: 2, workspace: workspace)
            let c = TestWindow.new(id: 3, workspace: workspace)
            return (workspace, a, b, c)
        }
        private func secondScreen() -> Workspace {
            let side = TestMonitor(displayId: "side", name: "Side", x: 1920)
            unsafe testMonitors = monitorInfos + [side]
            DisplayLayoutState.shared.reconcileMonitors(monitorInfos)
            return side.activeWorkspace
        }

        @Test func localDragMovesWholeSiblingAndLatchesItsEntireRegion() throws {
            let (workspace, a, _, _) = setupThree()
            workspace.layout.resize(1, by: 200, in: workspace.layoutRect, gap: 8)
            let before = workspace.tiledFrames
            let mouse = MouseTiling()
            defer { mouse.cancel() }
            mouse.observe(a, frame: try #require(before[1]))
            mouse.drag(at: before[2]!.center, on: workspace)
            #expect(workspace.layout.windowIds == [2, 3, 1])
            #expect(abs(workspace.tiledFrames[1]!.width - before[1]!.width) < 0.001)
            let swapped = workspace.layout
            mouse.drag(at: before[3]!.center, on: workspace)
            #expect(workspace.layout == swapped)
            mouse.finish(at: before[3]!.center, on: workspace)
            #expect(workspace.layout == swapped)
            #expect(currentlyManipulatedWithMouseWindowId == nil)
        }

        @Test func crossingParentSwapsWindowsAndKeepsThatModeForRestOfGesture() throws {
            let (workspace, _, _, c) = setupThree()
            let mouse = MouseTiling()
            defer { mouse.cancel() }
            let before = workspace.tiledFrames
            mouse.observe(c, frame: try #require(before[3]))
            mouse.drag(at: before[1]!.center, on: workspace)
            #expect(workspace.layout.windowIds == [3, 2, 1])
            let next = try #require(workspace.tiledFrames[2])
            mouse.drag(at: next.center, on: workspace)
            #expect(workspace.layout.windowIds == [2, 3, 1])
            mouse.finish(at: next.center, on: workspace)
            #expect(focus.windowOrNil === c)
        }

        @Test func crossScreenHoverPreviewsAndDropDiscardsSourceSwaps() throws {
            let (source, a, _, _) = setupThree()
            let destination = secondScreen()
            TestWindow.new(id: 4, workspace: destination)
            let original = source.layout
            let mouse = MouseTiling()
            let frame = try #require(source.tiledFrames[1])
            mouse.observe(a, frame: frame)
            mouse.drag(at: source.tiledFrames[2]!.center, on: source)
            #expect(source.layout != original)
            let sourceBeforeHover = source.layout
            let targetBeforeHover = destination.layout
            mouse.drag(at: destination.layoutRect.center, on: destination)
            #expect(source.layout == sourceBeforeHover && destination.layout == targetBeforeHover)
            #expect(a.workspace === source)
            #expect(mouse.preview?.workspace === destination)
            mouse.finish(at: destination.layoutRect.center, on: destination)
            var expected = original
            expected.remove(1)
            #expect(source.layout == expected)
            #expect(a.workspace === destination && destination.layout.windowIds == [4, 1])
            #expect(focus.windowOrNil === a)
            #expect(mouse.preview == nil)
        }

        @Test func cancellationRestoresSourceAndNeverChangesDestination() throws {
            let (source, a, _, _) = setupThree()
            let destination = secondScreen()
            let before = source.layout
            let mouse = MouseTiling()
            mouse.observe(a, frame: try #require(source.tiledFrames[1]))
            mouse.drag(at: source.tiledFrames[2]!.center, on: source)
            mouse.drag(at: destination.layoutRect.center, on: destination)
            mouse.cancel()
            #expect(source.layout == before)
            #expect(destination.layout.windowIds.isEmpty)
            #expect(a.workspace === source && currentlyManipulatedWithMouseWindowId == nil)
        }

        @Test func independentCreationCancelsSharedGestureBeforeInserting() throws {
            let (workspace, a, _, _) = setupThree()
            let original = workspace.layout
            let mouse = MouseTiling.shared
            mouse.observe(a, frame: try #require(workspace.tiledFrames[1]))
            mouse.drag(at: workspace.tiledFrames[2]!.center, on: workspace)
            let newcomer = TestWindow.new(id: 4, workspace: workspace)
            var expected = original
            expected.insert(4, beside: 1, in: workspace.layoutRect, gap: 8)
            #expect(workspace.layout == expected)
            mouse.cancel()
            #expect(newcomer.isRegistered && workspace.layout.windowIds.contains(4))
        }

        @Test func staleGestureCannotResurrectClosedWindowOrOverwriteExternalEdit() throws {
            let (workspace, a, _, _) = setupThree()
            let mouse = MouseTiling()
            let original = try #require(workspace.tiledFrames[1])
            mouse.observe(a, frame: original)
            workspace.flipOrientation()
            let external = workspace.layout
            mouse.cancel()
            #expect(workspace.layout == external)
            mouse.observe(a, frame: original)
            workspace.state.removeWindow(a, remember: false)
            mouse.finish(at: workspace.layoutRect.center, on: workspace)
            #expect(!workspace.layout.windowIds.contains(1))
            #expect(Set(workspace.layout.windowIds) == [2, 3])
        }

        @Test func liveDragWritesNeighborsAndReleaseWritesDraggedWindow() async throws {
            let (workspace, a, b, _) = setupThree()
            try await workspace.layoutWorkspace()
            let first = try #require(await a.getAxRect(.nonCancellable))
            let target = try #require(await b.getAxRect(.nonCancellable))
            let mouse = MouseTiling()
            mouse.observe(a, frame: first)
            mouse.drag(at: target.center, on: workspace)
            try await workspace.layoutWorkspace()
            #expect(try await a.getAxRect(.nonCancellable)?.topLeftCorner == first.topLeftCorner)
            #expect(try await b.getAxRect(.nonCancellable)?.minX == first.minX)
            mouse.finish(at: target.center, on: workspace)
            try await workspace.layoutWorkspace()
            #expect(try await a.getAxRect(.nonCancellable)?.minX == target.minX)
        }

        @Test func resizeUsesAbsoluteDeltaClampsAndDoesNotBecomeMove() throws {
            let (workspace, a, _, _) = setupThree()
            let original = try #require(workspace.tiledFrames[1])
            let mouse = MouseTiling()
            var frame = original
            frame.width += 40
            mouse.observe(a, frame: frame)
            frame.width += 30
            mouse.observe(a, frame: frame)
            #expect(abs(workspace.tiledFrames[1]!.width - original.width - 70) < 0.001)
            let resized = workspace.layout
            mouse.drag(at: workspace.tiledFrames[2]!.center, on: workspace)
            #expect(workspace.layout == resized)
            mouse.finish(at: frame.center, on: workspace)
            #expect(workspace.layout == resized)
        }

        @Test(arguments: [Orientation.h, .v], [CGFloat(5), 32])
        func resizingLeadingEdgeDoesNotBecomeSwap(axis: Orientation, delta: CGFloat) throws {
            ConfigurationApplication.shared.apply("gap = 4")
            let workspace = focus.workspace
            workspace.orientationOverride = axis
            workspace.recover()
            TestWindow.new(id: 1, workspace: workspace)
            let second = TestWindow.new(id: 2, workspace: workspace)
            let original = try #require(workspace.tiledFrames[2])
            var frame = original
            if axis == .h {
                frame.topLeftX -= delta
                frame.width += delta
            } else {
                frame.topLeftY -= delta
                frame.height += delta
            }
            let edge =
                axis == .h
                ? CGPoint(x: frame.minX, y: frame.center.y) : CGPoint(x: frame.center.x, y: frame.minY)
            let mouse = MouseTiling()
            defer { mouse.cancel() }
            mouse.observe(second, frame: frame)
            mouse.drag(at: edge, on: workspace)
            mouse.observe(second, frame: frame)
            mouse.finish(at: edge, on: workspace)
            #expect(workspace.layout.windowIds == [1, 2])
            let resized = try #require(workspace.tiledFrames[2])
            #expect(abs(resized.getDimension(axis) - frame.getDimension(axis)) < 0.001)
        }

        @Test func movingWindowWithAppRoundedSizeDoesNotBecomeResize() throws {
            let workspace = focus.workspace
            let first = TestWindow.new(id: 1, workspace: workspace)
            TestWindow.new(id: 2, workspace: workspace)
            let original = try #require(workspace.tiledFrames[1])
            first.lastAppliedLayoutPhysicalRect = original
            var actual = original
            actual.width -= 12  // A terminal may round the requested size to its character grid.
            #expect(!first.observeAppliedSize(requested: original.size, actual: actual.size))
            actual.topLeftX += 30
            let mouse = MouseTiling()
            defer { mouse.cancel() }
            mouse.observe(first, frame: actual)
            mouse.drag(at: workspace.tiledFrames[2]!.center, on: workspace)
            #expect(workspace.layout.windowIds == [2, 1])
        }

        @Test func crossScreenHoverReleasesPreviousSwapRegion() throws {
            let source = focus.workspace
            let first = TestWindow.new(id: 1, workspace: source)
            TestWindow.new(id: 2, workspace: source)
            let destination = secondScreen()
            source.layout.resize(1, by: -200, in: source.layoutRect, gap: CGFloat(config.gap))
            let original = source.layout
            let before = source.tiledFrames
            let oldTarget = try #require(before[2])
            let mouse = MouseTiling()
            defer { mouse.cancel() }
            mouse.observe(first, frame: try #require(before[1]))
            mouse.drag(at: oldTarget.center, on: source)
            #expect(source.layout.windowIds == [2, 1])
            let newTarget = try #require(source.tiledFrames[2])
            let left = max(oldTarget.minX, newTarget.minX)
            let right = min(oldTarget.maxX, newTarget.maxX)
            #expect(left < right)
            let returnPoint = CGPoint(x: (left + right) / 2, y: newTarget.center.y)
            mouse.drag(at: destination.layoutRect.center, on: destination)
            mouse.drag(at: returnPoint, on: source)
            #expect(source.layout.windowIds == original.windowIds)
            #expect(first.workspace === source && destination.layout.windowIds.isEmpty)
            let swapped = source.layout
            mouse.finish(at: returnPoint, on: source)
            #expect(source.layout == swapped)
        }

        @Test func floatingTransferIsDeferredAndRemainsFloating() throws {
            let source = focus.workspace
            let destination = secondScreen()
            let frame = Rect(topLeftX: 100, topLeftY: 100, width: 450, height: 300)
            let floating = TestWindow.new(id: 1, workspace: source, kind: .floating, rect: frame)
            let mouse = MouseTiling()
            mouse.observe(floating, frame: frame)
            mouse.drag(at: destination.layoutRect.center, on: destination)
            #expect(floating.workspace === source && mouse.preview?.floating == true)
            mouse.finish(at: destination.layoutRect.center, on: destination)
            #expect(floating.workspace === destination && floating.kind == .floating)
            #expect(source.layout.windowIds.isEmpty && destination.layout.windowIds.isEmpty)
        }

        @Test func ordinaryMouseReleaseDoesNotInvalidateObservationRestoration() async throws {
            let workspace = focus.workspace
            let a = TestWindow.new(id: 1, workspace: workspace)
            workspace.state.removeWindow(a, remember: true)
            try await resetManipulatedWithMouseIfPossible()
            let returned = TestWindow.new(id: 1, workspace: workspace)
            #expect(workspace.state.restoreWindow(newlyDetectedWindow: returned))
        }

        @Test func displayGeometryChangeInvalidatesPendingDrop() throws {
            let (workspace, a, _, _) = setupThree()
            let mouse = MouseTiling()
            mouse.observe(a, frame: try #require(workspace.tiledFrames[1]))
            workspace.workspaceMonitor = TestMonitor(displayId: workspace.name, name: "Moved", x: 100)
            let before = workspace.layout
            mouse.finish(at: workspace.tiledFrames[2]!.center, on: workspace)
            #expect(workspace.layout == before && currentlyManipulatedWithMouseWindowId == nil)
        }
    }
}
