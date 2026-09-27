import Common
import Testing

@testable import AppBundle

extension CoreTests {
    @MainActor struct ResizeCommandTest {
        init() { setUpWorkspacesForTests() }

        @Test func growsAndShrinksByFiftyDistributingSpaceAcrossSiblings() async {
            let root = focus.workspace.rootTilingContainer
            let first = TestWindow.new(id: 1, parent: root, adaptiveWeight: 200)
            let second = TestWindow.new(id: 2, parent: root, adaptiveWeight: 200)
            let third = TestWindow.new(id: 3, parent: root, adaptiveWeight: 200)
            _ = first.focusWindow()
            let grow = await Action.grow.run()
            #expect(grow.exitCode == .succ)
            #expect(first.hWeight == 250 && second.hWeight == 175 && third.hWeight == 175)
            let shrink = await Action.shrink.run()
            #expect(shrink.exitCode == .succ)
            #expect(first.hWeight == 200 && second.hWeight == 200 && third.hWeight == 200)
        }

        @Test func resizeUsesImmediateSplitOrientation() async {
            let root = focus.workspace.rootTilingContainer
            let vertical = TilingContainer.newVTiles(parent: root, adaptiveWeight: 200)
            let first = TestWindow.new(id: 1, parent: vertical, adaptiveWeight: 200)
            let second = TestWindow.new(id: 2, parent: vertical, adaptiveWeight: 200)
            let sibling = TestWindow.new(id: 3, parent: root, adaptiveWeight: 200)
            _ = first.focusWindow()
            await Action.grow.run()
            #expect(first.vWeight == 250 && second.vWeight == 150)
            #expect(sibling.hWeight == 200 && vertical.hWeight == 200)
        }

        @Test func singleWindowAndFloatingWindowFailWithoutChangingSize() async {
            let workspace = focus.workspace
            let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer, adaptiveWeight: 200)
            _ = window.focusWindow()
            let single = await Action.grow.run()
            #expect(single.exitCode == .fail)
            #expect(window.hWeight == 200)
            window.bindAsFloatingWindow(to: workspace)
            let floating = await Action.shrink.run()
            #expect(floating.exitCode == .fail)
            #expect(window.isFloating)
        }
    }
}
