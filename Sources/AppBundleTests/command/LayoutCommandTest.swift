import AppKit
import Common
import Testing

@testable import AppBundle

extension CoreTests {
    @MainActor
    struct LayoutCommandTest {
        var name: String { String(describing: Self.self) }
        init() async throws { setUpWorkspacesForTests() }

        @Test func testChangeOrientation() async {
            let root = workspaceForTest(name).rootTilingContainer.apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0)
            }
            assertEquals(root.orientation, .h)

            await Action.toggleOrientation.run()
            assertEquals(root.orientation, .v)
            assertEquals(root.layoutDescription, .v_tiles([.window(1), .window(2)]))
        }

        @Test func testEmptyWorkspace_changeOrientation() async {
            let workspace = workspaceForTest(name)
            assertTrue(workspace.isEffectivelyEmpty)

            let result = await Action.toggleOrientation
                .run()
            assertEquals(result.exitCode.rawValue, 0)
            assertEquals(workspace.rootTilingContainer.orientation, .v)
        }

        @Test func testEmptyWorkspace_floating_fails() async {
            let workspace = workspaceForTest(name)
            let result = await Action.toggleFloating
                .run()
            assertEquals(result.exitCode.rawValue, 2)
            assertEquals(result.stderr, [noWindowIsFocused])
            assertTrue(workspace.isEffectivelyEmpty)
        }

        @Test func testTilingToFloating() async {
            let workspace = workspaceForTest(name)
            let root = workspace.rootTilingContainer.apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0)
            }

            await Action.toggleFloating.run()
            assertEquals(root.layoutDescription, .h_tiles([.window(2)]))
            assertEquals(workspace.floatingWindows.map(\.windowId), [1])
            assertEquals(focus.windowOrNil?.windowId, 1)
        }

        @Test func testFloatingToTiling() async {
            let workspace = workspaceForTest(name)
            workspace.floatingWindowsContainer.apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            }
            assertEquals(workspace.floatingWindows.map(\.windowId), [1])

            await Action.toggleFloating.run()
            assertEquals(workspace.floatingWindows, [])
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1)]))
        }

        @Test func testChangeTilingLayoutOnFloatingWindow_fails() async {
            let workspace = workspaceForTest(name)
            workspace.floatingWindowsContainer.apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            }

            let result = await Action.toggleOrientation.run()
            assertEquals(result.exitCode.rawValue, 2)
            assertEquals(result.stderr, ["The window is non-tiling"])
            assertEquals(workspace.floatingWindows.map(\.windowId), [1])
        }

        @Test func testTogglesAcrossFloatingAndTiling() async {
            let workspace = workspaceForTest(name)
            workspace.floatingWindowsContainer.apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            }

            // The window is floating, so [.floating, .tiling] picks .tiling
            await Action.toggleFloating.run()
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1)]))

            // Now it's tiled, so the same toggle picks .floating
            await Action.toggleFloating.run()
            assertEquals(workspace.floatingWindows.map(\.windowId), [1])
        }

    }
}
