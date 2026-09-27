import AppKit
import Testing

@testable import AppBundle

extension CoreTests {
    @MainActor
    struct TreeNodeTest {
        var name: String { String(describing: Self.self) }
        init() async throws { setUpWorkspacesForTests() }

        @Test func testChildParentCyclicReferenceMemoryLeak() {
            let workspace = workspaceForTest(name)  // Don't cache root node
            let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)

            expectTrue(window.parent != nil)
            workspace.rootTilingContainer.unbindFromParent()
            expectTrue(window.parent == nil)
        }

        @Test func testIsEffectivelyEmpty() {
            let workspace = workspaceForTest(name)

            expectTrue(workspace.isEffectivelyEmpty)
            weak let window: TestWindow? = .new(id: 1, parent: workspace.rootTilingContainer)
            expectNotEqual(window, nil)
            expectTrue(!workspace.isEffectivelyEmpty)
            window!.unbindFromParent()
            expectTrue(workspace.isEffectivelyEmpty)

            // Don't save to local variable
            TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
            expectTrue(!workspace.isEffectivelyEmpty)
        }

        @Test func nestedGroupsAlwaysAlternateOrientation() {
            let workspace = workspaceForTest(name)
            let root = workspace.rootTilingContainer
            let nested = TilingContainer.newHTiles(parent: root, adaptiveWeight: 1)
            TestWindow.new(id: 1, parent: root)
            TestWindow.new(id: 2, parent: nested)
            TestWindow.new(id: 3, parent: nested)
            workspace.normalizeContainers()
            #expect(root.orientation == .h)
            #expect(nested.orientation == .v)
            #expect(nested.children.count == 2)
            nested.changeOrientation(.h)
            #expect(root.orientation == .v)
            #expect(nested.orientation == .h)
        }

        @Test func testNormalizeContainers_dontRemoveRoot() {
            let workspace = workspaceForTest(name)
            weak let root = workspace.rootTilingContainer
            func test() {
                expectNotEqual(root, nil)
                expectTrue(root!.isEffectivelyEmpty)
                workspace.normalizeContainers()
                expectNotEqual(root, nil)
            }
            test()
        }

        @Test func testNormalizeContainers_singleWindowChild() {
            let workspace = workspaceForTest(name)
            workspace.rootTilingContainer.apply {
                TestWindow.new(id: 0, parent: $0)
                TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                    TestWindow.new(id: 1, parent: $0)
                }
            }
            workspace.normalizeContainers()
            assertEquals(
                .h_tiles([.window(0), .window(1)]),
                workspace.rootTilingContainer.layoutDescription,
            )
        }

        @Test func testNormalizeContainers_removeEffectivelyEmpty() {
            let workspace = workspaceForTest(name)
            workspace.rootTilingContainer.apply {
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                    _ = TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1)
                }
            }
            assertEquals(workspace.rootTilingContainer.children.count, 1)
            workspace.normalizeContainers()
            assertEquals(workspace.rootTilingContainer.children.count, 0)
        }

        @Test func testNormalizeContainers_flattenContainers() {
            let workspace = workspaceForTest(name)  // Don't cache root node
            workspace.rootTilingContainer.apply {
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                    TestWindow.new(id: 1, parent: $0, adaptiveWeight: 1)
                }
            }
            workspace.normalizeContainers()
            expectTrue(workspace.rootTilingContainer.children.singleOrNil() is TestWindow)
        }
    }
}
