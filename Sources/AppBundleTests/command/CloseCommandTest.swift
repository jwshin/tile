import AppKit
import Common
import Testing

@testable import AppBundle

extension CoreTests {
    @MainActor
    struct CloseCommandTest {
        var name: String { String(describing: Self.self) }
        init() async throws { setUpWorkspacesForTests() }

        @Test func testSimple() async {
            workspaceForTest(name).rootTilingContainer.apply {
                _ = TestWindow.new(id: 1, parent: $0).focusWindow()
                TestWindow.new(id: 2, parent: $0)
            }

            assertEquals(focus.windowOrNil?.windowId, 1)
            assertEquals(focus.workspace.rootTilingContainer.children.count, 2)

            await Action.close.applyToModel()

            assertEquals(focus.windowOrNil?.windowId, 2)
            assertEquals(focus.workspace.rootTilingContainer.children.count, 1)
        }

    }
}
