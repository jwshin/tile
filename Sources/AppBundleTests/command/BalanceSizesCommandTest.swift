import AppKit
import Common
import Testing

@testable import AppBundle

extension CoreTests {
    @MainActor
    struct BalanceSizesCommandTest {
        var name: String { String(describing: Self.self) }
        init() async throws { setUpWorkspacesForTests() }

        @Test func testBalanceSizesCommand() async {
            let workspace = workspaceForTest(name).apply { wsp in
                wsp.rootTilingContainer.apply {
                    TestWindow.new(id: 1, parent: $0).setWeight(wsp.rootTilingContainer.orientation, 1)
                    TestWindow.new(id: 2, parent: $0).setWeight(wsp.rootTilingContainer.orientation, 2)
                    TestWindow.new(id: 3, parent: $0).setWeight(wsp.rootTilingContainer.orientation, 3)
                }
            }

            await Action.balanceSizes
                .run()

            for window in workspace.rootTilingContainer.children {
                assertEquals(window.getWeight(workspace.rootTilingContainer.orientation), 1)
            }
        }
    }
}
