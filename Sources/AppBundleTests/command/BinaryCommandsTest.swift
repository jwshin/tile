import AppKit
import Common
import Testing

@testable import AppBundle

extension CoreTests {
    @MainActor struct BinaryCommandsTest {
        init() { setUpWorkspacesForTests() }

        @Test func directionalMoveReinsertsAndSwapPreservesFrames() async {
            let workspace = focus.workspace
            let a = TestWindow.new(id: 1, workspace: workspace)
            let b = TestWindow.new(id: 2, workspace: workspace)
            let c = TestWindow.new(id: 3, workspace: workspace)
            _ = a.focusWindow()
            #expect(await Action.moveRight.applyToModel().exitCode == .succ)
            #expect(workspace.layout.windowIds.count == 3)
            let frames = workspace.tiledFrames
            #expect(frames[1]!.minX >= frames[2]!.maxX)
            #expect(await Action.swapLeft.applyToModel().exitCode == .succ)
            #expect(workspace.tiledFrames[1]?.topLeftCorner == frames[2]?.topLeftCorner)
            #expect(focus.windowOrNil === a)
            #expect(b.isRegistered && c.isRegistered)
        }

        @Test func closeCollapsesSplitAndFocusesRemainingWindow() async {
            let workspace = focus.workspace
            let a = TestWindow.new(id: 1, workspace: workspace)
            let b = TestWindow.new(id: 2, workspace: workspace)
            _ = a.focusWindow()
            await Action.close.applyToModel()
            #expect(!a.isRegistered)
            #expect(focus.windowOrNil === b)
            #expect(workspace.tiledFrames[2]?.size == workspace.layoutRect.size)
        }

        @Test func resizeToggleAndFloatingUseTheSameModel() async throws {
            let workspace = focus.workspace
            let a = TestWindow.new(id: 1, workspace: workspace)
            TestWindow.new(id: 2, workspace: workspace)
            _ = a.focusWindow()
            let width = workspace.tiledFrames[1]!.width
            #expect(await Action.grow.applyToModel().exitCode == .succ)
            #expect(abs(workspace.tiledFrames[1]!.width - width - 50) < 0.001)
            await Action.toggleSplit.applyToModel()
            #expect(workspace.tiledFrames[1]?.width == workspace.layoutRect.width)
            await Action.toggleFloating.applyToModel()
            #expect(a.kind == .floating && !workspace.layout.windowIds.contains(1))
            await Action.toggleFloating.applyToModel()
            #expect(a.kind == .tiled && Set(workspace.layout.windowIds) == Set([1, 2]))
            #expect(await Action.balanceSizes.applyToModel().exitCode == .succ)
        }

        @Test func spatialFocusIncludesFloatingWithoutMutatingTree() async {
            let workspace = focus.workspace
            let tiled = TestWindow.new(id: 1, workspace: workspace)
            let floating = TestWindow.new(
                id: 2, workspace: workspace, kind: .floating,
                rect: Rect(topLeftX: 1300, topLeftY: 200, width: 400, height: 400))
            let original = workspace.layout
            _ = tiled.focusWindow()
            await Action.focusRight.applyToModel()
            #expect(focus.windowOrNil === floating)
            await Action.focusLeft.applyToModel()
            #expect(focus.windowOrNil === tiled)
            #expect(workspace.layout == original)
        }

        @Test func floatingDialogDoesNotCollapseExpandedTiledWindow() async throws {
            let workspace = focus.workspace
            let editor = TestWindow.new(id: 1, workspace: workspace)
            TestWindow.new(id: 2, workspace: workspace)
            _ = editor.focusWindow()
            await Action.fullscreen.applyToModel()
            let dialog = TestWindow.new(
                id: 3, workspace: workspace, kind: .floating,
                rect: Rect(topLeftX: 300, topLeftY: 300, width: 400, height: 300))
            _ = dialog.focusWindow()
            try await workspace.layoutWorkspace()
            let frame = try #require(await editor.getAxRect(.nonCancellable))
            #expect(editor.isFullscreen)
            #expect(frame.size == workspace.workspaceMonitor.visibleRectPaddedByOuterGaps.size)
        }

        @Test func removedBindingsAreRejected() {
            for action in ["join-left", "flatten-layout", "toggle-orientation"] {
                #expect(!parseConfig("[bindings]\nalt-h = '\(action)'").allowReloadConfig)
            }
        }
    }
}
