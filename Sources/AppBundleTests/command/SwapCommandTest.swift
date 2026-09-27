import AppKit
import Common
import Testing

@testable import AppBundle

extension CoreTests {
    @MainActor
    struct SwapCommandTest {
        var name: String { String(describing: Self.self) }
        init() async throws { setUpWorkspacesForTests() }

        @Test func testSwap_swapWindows_Directional() async {
            let root = workspaceForTest(name).rootTilingContainer.apply {
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                    assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                    TestWindow.new(id: 2, parent: $0)
                }
                TestWindow.new(id: 3, parent: $0)
            }

            await Action.swapRight.run()
            assertEquals(
                root.layoutDescription,
                .h_tiles([
                    .v_tiles([.window(3), .window(2)]),
                    .window(1),
                ]))
            assertEquals(focus.windowOrNil?.windowId, 1)
            assertEquals(root.mostRecentWindowRecursive?.windowId, 1)

            await Action.swapLeft.run()
            assertEquals(
                root.layoutDescription,
                .h_tiles([
                    .v_tiles([.window(1), .window(2)]),
                    .window(3),
                ]))
            assertEquals(focus.windowOrNil?.windowId, 1)
            assertEquals(root.mostRecentWindowRecursive?.windowId, 1)

            await Action.swapDown.run()
            assertEquals(
                root.layoutDescription,
                .h_tiles([
                    .v_tiles([.window(2), .window(1)]),
                    .window(3),
                ]))
            assertEquals(focus.windowOrNil?.windowId, 1)
            assertEquals(root.mostRecentWindowRecursive?.windowId, 1)

            await Action.swapUp.run()
            assertEquals(
                root.layoutDescription,
                .h_tiles([
                    .v_tiles([.window(1), .window(2)]),
                    .window(3),
                ]))
            assertEquals(focus.windowOrNil?.windowId, 1)
            assertEquals(root.mostRecentWindowRecursive?.windowId, 1)
        }

    }
}
