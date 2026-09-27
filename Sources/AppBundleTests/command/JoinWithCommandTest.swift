import AppKit
import Common
import Testing

@testable import AppBundle

extension CoreTests {
    @MainActor
    struct JoinWithCommandTest {
        var name: String { String(describing: Self.self) }
        init() async throws { setUpWorkspacesForTests() }

        @Test func testMoveIn() async {
            let root = workspaceForTest(name).rootTilingContainer.apply {
                TestWindow.new(id: 0, parent: $0)
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0)
            }

            await Action.joinRight.run()
            assertEquals(
                root.layoutDescription,
                .h_tiles([
                    .window(0),
                    .v_tiles([
                        .window(1),
                        .window(2),
                    ]),
                ]))
        }
    }
}
