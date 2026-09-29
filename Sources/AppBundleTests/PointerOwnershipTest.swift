import AppKit
import Testing

@testable import AppBundle

extension CoreTests {
    @MainActor struct PointerOwnershipTest {
        init() { setUpWorkspacesForTests() }
        private let main = TestMonitor(displayId: "main", name: "Main", x: 0, isMain: true)
        private let side = TestMonitor(displayId: "side", name: "Side", x: 1920)

        @Test func ownersKeepGesturesPreviewsAndFrameWritesIndependent() async throws {
            let firstPointer = TestPointerAdapter()
            let first = DisplayLayoutState(monitors: [main, side], pointer: firstPointer)
            let source = first.mainWorkspace
            let a = TestWindow.new(id: 1, workspace: source)
            TestWindow.new(id: 2, workspace: source)
            let original = source.layout
            let frame = try #require(source.tiledFrames[1])
            first.updatePointer(a, frame: frame, at: source.tiledFrames[2]!.center, on: source)
            let swapped = source.layout
            #expect(swapped != original)
            first.updatePointer(a, frame: frame, at: side.rect.center, on: first.workspace(for: side))
            #expect(firstPointer.preview != nil)

            // Even constructing another owner used to cancel the shared gesture.
            let secondPointer = TestPointerAdapter()
            let second = DisplayLayoutState(monitors: [main, side], pointer: secondPointer)
            let b = TestWindow.new(id: 1, workspace: second.mainWorkspace)
            let c = TestWindow.new(id: 2, workspace: second.mainWorkspace)
            try await second.mainWorkspace.layoutWorkspace()
            let bFrame = try #require(second.mainWorkspace.tiledFrames[1])
            #expect(try await b.getAxRect(.nonCancellable)?.size == bFrame.size)
            #expect(first.manipulatedWindow === a && source.layout == swapped)

            second.updatePointer(b, frame: bFrame, at: side.rect.center, on: second.workspace(for: side))
            #expect(secondPointer.preview != nil && firstPointer.preview != nil)
            second.removeWindow(c, remember: false)
            #expect(second.manipulatedWindow == nil && secondPointer.preview == nil)
            second.finishPointer(at: bFrame.center, on: second.mainWorkspace)
            #expect(first.manipulatedWindow === a && firstPointer.preview != nil)
            #expect(source.layout == swapped)
            first.cancelPointer()
            #expect(source.layout == original && firstPointer.preview == nil)
        }

        @Test func foreignWindowsAndDestinationsCannotChangeAnOwnedGesture() throws {
            let first = DisplayLayoutState(monitors: [main], pointer: TestPointerAdapter())
            let second = DisplayLayoutState(monitors: [main], pointer: TestPointerAdapter())
            let a = TestWindow.new(id: 1, workspace: first.mainWorkspace)
            let peer = TestWindow.new(id: 2, workspace: first.mainWorkspace)
            let foreign = TestWindow.new(id: 1, workspace: second.mainWorkspace)
            let frame = try #require(first.mainWorkspace.tiledFrames[1])
            first.updatePointer(foreign, frame: frame, at: frame.center, on: first.mainWorkspace)
            #expect(first.manipulatedWindow == nil)
            first.updatePointer(a, frame: frame, at: frame.center, on: first.mainWorkspace)
            let before = first.mainWorkspace.layout
            first.updatePointer(a, frame: frame, at: frame.center, on: second.mainWorkspace)
            first.updatePointer(peer, frame: frame, at: frame.center, on: first.mainWorkspace)
            first.finishPointer(at: frame.center, on: second.mainWorkspace)
            #expect(first.manipulatedWindow === a)
            #expect(first.mainWorkspace.layout == before && a.workspace === first.mainWorkspace)
            first.cancelPointer()
        }

        @Test func ownLifecycleCancelsBeforeInsertionAndBlocksSamplesUntilRelease() throws {
            let pointer = TestPointerAdapter()
            let state = DisplayLayoutState(monitors: [main], pointer: pointer)
            let workspace = state.mainWorkspace
            let a = TestWindow.new(id: 1, workspace: workspace)
            TestWindow.new(id: 2, workspace: workspace)
            let original = workspace.layout
            let frame = try #require(workspace.tiledFrames[1])
            state.updatePointer(a, frame: frame, at: workspace.tiledFrames[2]!.center, on: workspace)
            let newcomer = TestWindow.new(id: 3, workspace: workspace)
            var expected = original
            expected.insert(3, beside: 1, in: workspace.layoutRect, gap: 8)
            #expect(workspace.layout == expected)
            #expect(state.manipulatedWindow == nil && state.isHandlingPointer)
            state.updatePointer(a, frame: frame, at: workspace.tiledFrames[2]!.center, on: workspace)
            #expect(workspace.layout == expected && state.manipulatedWindow == nil)
            pointer.isButtonDown = false
            state.finishPointer(at: frame.center, on: workspace)
            state.cancelPointer()
            #expect(workspace.layout == expected && newcomer.isRegistered && !state.isHandlingPointer)
            pointer.isButtonDown = true
            let fresh = try #require(workspace.tiledFrames[1])
            state.updatePointer(a, frame: fresh, at: fresh.center, on: workspace)
            #expect(state.manipulatedWindow === a)
            state.cancelPointer()
        }

        @Test func equalWindowIdsDoNotSuppressOtherOwnersSizeFeedback() throws {
            let first = DisplayLayoutState(monitors: [main], pointer: TestPointerAdapter())
            let second = DisplayLayoutState(monitors: [main], pointer: TestPointerAdapter())
            let a = TestWindow.new(id: 1, workspace: first.mainWorkspace)
            let b = TestWindow.new(id: 1, workspace: second.mainWorkspace)
            let frame = try #require(first.mainWorkspace.tiledFrames[1])
            first.updatePointer(a, frame: frame, at: frame.center, on: first.mainWorkspace)
            let requested = Rect(topLeftX: 8, topLeftY: 8, width: 400, height: 300)
            let actual = CGSize(width: 600, height: 350)
            b.lastAppliedLayoutPhysicalRect = requested
            #expect(!b.observeAppliedSize(requested: requested.size, actual: actual))
            b.lastAppliedLayoutPhysicalRect = requested
            #expect(b.observeAppliedSize(requested: requested.size, actual: actual))
            #expect(b.minimumSize == actual && first.manipulatedWindow === a)
            first.cancelPointer()
        }

        @Test func releaseAfterDisablingClearsCancellationForNextGesture() async throws {
            let pointer = TestPointerAdapter()
            let state = DisplayLayoutState(monitors: monitorInfos, pointer: pointer)
            DisplayLayoutState.shared = state
            let a = TestWindow.new(id: 1, workspace: state.mainWorkspace)
            let frame = try #require(state.mainWorkspace.tiledFrames[1])
            state.updatePointer(a, frame: frame, at: frame.center, on: state.mainWorkspace)
            _ = try await ActionExecution.shared.execute(.toggleTiling, from: .menu)
            #expect(!ConfigurationApplication.shared.isEnabled && state.isHandlingPointer)
            #expect(state.manipulatedWindow == nil)
            pointer.isButtonDown = false
            try await resetManipulatedWithMouseIfPossible()
            #expect(!state.isHandlingPointer)
            _ = try await ActionExecution.shared.execute(.toggleTiling, from: .menu)
            pointer.isButtonDown = true
            state.updatePointer(a, frame: frame, at: frame.center, on: state.mainWorkspace)
            #expect(state.manipulatedWindow === a)
            state.cancelPointer()
        }

        @Test func pointerSamplesInvalidateOnlyTheirOwnersRestoration() throws {
            let first = DisplayLayoutState(monitors: [main], pointer: TestPointerAdapter())
            let second = DisplayLayoutState(monitors: [main], pointer: TestPointerAdapter())
            let a = TestWindow.new(id: 1, workspace: first.mainWorkspace)
            let lostA = TestWindow.new(id: 2, workspace: first.mainWorkspace)
            let lostB = TestWindow.new(id: 2, workspace: second.mainWorkspace)
            first.removeWindow(lostA, remember: true)
            second.removeWindow(lostB, remember: true)
            let frame = try #require(first.mainWorkspace.tiledFrames[1])
            first.updatePointer(a, frame: frame, at: frame.center, on: first.mainWorkspace)
            first.finishPointer(at: frame.center, on: first.mainWorkspace)
            let returnedA = TestWindow.new(id: 2, workspace: first.mainWorkspace)
            let returnedB = TestWindow.new(id: 2, workspace: second.mainWorkspace)
            #expect(!first.restoreWindow(newlyDetectedWindow: returnedA))
            #expect(second.restoreWindow(newlyDetectedWindow: returnedB))
        }
    }
}
