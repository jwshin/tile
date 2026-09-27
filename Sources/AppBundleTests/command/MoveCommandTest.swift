import AppKit
import Common
import Testing

@testable import AppBundle

extension CoreTests {
    @MainActor
    struct MoveCommandTest {
        var name: String { String(describing: Self.self) }
        init() async throws { setUpWorkspacesForTests() }

        @Test func testMove_swapWindows() async {
            let root = workspaceForTest(name).rootTilingContainer.apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0)
            }

            await Action.moveRight.applyToModel()
            assertEquals(root.layoutDescription, .h_tiles([.window(2), .window(1)]))
        }

        @Test func testMoveInto_normalizesDestinationGroup() async {
            let root = workspaceForTest(name).rootTilingContainer.apply {
                TestWindow.new(id: 0, parent: $0)
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                    TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                        TestWindow.new(id: 2, parent: $0)
                    }
                }
            }

            await Action.moveRight.applyToModel()
            assertEquals(
                root.layoutDescription,
                .h_tiles([
                    .window(0),
                    .v_tiles([
                        .window(1),
                        .window(2),
                    ]),
                ]),
            )
        }

        @Test func testMove_mru() async {
            var window3: Window!
            let root = workspaceForTest(name).rootTilingContainer.apply {
                TestWindow.new(id: 0, parent: $0)
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                    TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                        TestWindow.new(id: 2, parent: $0)
                        window3 = TestWindow.new(id: 3, parent: $0)
                    }
                    TestWindow.new(id: 4, parent: $0)
                }
            }
            window3.markAsMostRecentChild()

            await Action.moveRight.applyToModel()
            assertEquals(
                root.layoutDescription,
                .h_tiles([
                    .window(0),
                    .v_tiles([
                        .h_tiles([
                            .window(1),
                            .window(2),
                            .window(3),
                        ]),
                        .window(4),
                    ]),
                ]),
            )
        }

        @Test func testSwap_preserveWeight() async {
            let root = workspaceForTest(name).rootTilingContainer
            let window1 = TestWindow.new(id: 1, parent: root, adaptiveWeight: 1)
            let window2 = TestWindow.new(id: 2, parent: root, adaptiveWeight: 2)
            _ = window2.focusWindow()

            await Action.moveLeft.applyToModel()
            assertEquals(window2.hWeight, 2)
            assertEquals(window1.hWeight, 1)
        }

        @Test func testMoveIn_newWeight() async {
            var window1: Window!
            var window2: Window!
            workspaceForTest(name).rootTilingContainer.apply {
                TestWindow.new(id: 0, parent: $0, adaptiveWeight: 1)
                window1 = TestWindow.new(id: 1, parent: $0, adaptiveWeight: 2)
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                    window2 = TestWindow.new(id: 2, parent: $0, adaptiveWeight: 1)
                }
            }
            _ = window1.focusWindow()

            await Action.moveRight.applyToModel()
            assertEquals(window2.hWeight, 1)
            assertEquals(window2.vWeight, 1)
            assertEquals(window1.vWeight, 1)
            assertEquals(window1.hWeight, 1)
        }

        @Test func testCreateImplicitContainer() async {
            let workspace = workspaceForTest(name)
            workspace.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0)
                assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
                TestWindow.new(id: 3, parent: $0)
            }

            let result = await Action.moveUp.applyToModel()
            assertEquals(
                workspace.layoutDescription,
                .workspace([
                    .v_tiles([
                        .window(2),
                        .h_tiles([.window(1), .window(3)]),
                    ])
                ]),
            )
            assertEquals(result.exitCode.rawValue, 0)
        }

        @Test func testMoveOut() async {
            let root = workspaceForTest(name).rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0)
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                    assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
                    TestWindow.new(id: 3, parent: $0)
                    TestWindow.new(id: 4, parent: $0)
                }
            }

            await Action.moveLeft.applyToModel()
            assertEquals(
                root.layoutDescription,
                .h_tiles([
                    .window(1),
                    .window(2),
                    .v_tiles([
                        .window(3),
                        .window(4),
                    ]),
                ]),
            )
        }

        @Test func testMoveOutWithNormalization_right() async {

            let workspace = workspaceForTest(name).apply {
                TestWindow.new(id: 1, parent: $0.rootTilingContainer)
                assertEquals(TestWindow.new(id: 2, parent: $0.rootTilingContainer).focusWindow(), true)
            }

            await Action.moveRight.applyToModel()
            assertEquals(
                workspace.rootTilingContainer.layoutDescription,
                .h_tiles([
                    .window(1),
                    .window(2),
                ]),
            )
            assertEquals(focus.windowOrNil?.windowId, 2)
        }

        @Test func testMoveOutWithNormalization_left() async {

            let workspace = workspaceForTest(name).apply {
                assertEquals(TestWindow.new(id: 1, parent: $0.rootTilingContainer).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0.rootTilingContainer)
            }

            await Action.moveLeft.applyToModel()
            assertEquals(
                workspace.rootTilingContainer.layoutDescription,
                .h_tiles([
                    .window(1),
                    .window(2),
                ]),
            )
            assertEquals(focus.windowOrNil?.windowId, 1)
        }
    }
}

extension TreeNode {
    var layoutDescription: LayoutDescription {
        return switch nodeCases {
        case .window(let window): .window(window.windowId)
        case .workspace(let workspace): .workspace(workspace.children.map(\.layoutDescription))
        case .floatingWindowsContainer(let container):
            .floatingWindowsContainer(container.children.map(\.layoutDescription))
        case .macosMinimizedWindowsContainer: .macosMinimized
        case .macosFullscreenWindowsContainer: .macosFullscreen
        case .macosHiddenAppsWindowsContainer: .macosHiddeAppWindow
        case .macosPopupWindowsContainer: .macosPopupWindowsContainer
        case .tilingContainer(let container):
            container.orientation == .h
                ? .h_tiles(container.children.map(\.layoutDescription))
                : .v_tiles(container.children.map(\.layoutDescription))
        }
    }
}

enum LayoutDescription: Equatable {
    case workspace([LayoutDescription])
    case h_tiles([LayoutDescription])
    case v_tiles([LayoutDescription])
    case floatingWindowsContainer([LayoutDescription])
    case window(UInt32)
    case macosPopupWindowsContainer
    case macosMinimized
    case macosHiddeAppWindow
    case macosFullscreen
}
