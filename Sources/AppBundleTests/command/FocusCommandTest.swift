import AppKit
import Common
import Testing

@testable import AppBundle

extension CoreTests {
    @MainActor
    struct FocusCommandTest {
        var name: String { String(describing: Self.self) }
        init() async throws { setUpWorkspacesForTests() }

        @Test func testFocus() {
            assertEquals(focus.windowOrNil, nil)
            workspaceForTest(name).rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0)
                assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
                TestWindow.new(id: 3, parent: $0)
            }
            assertEquals(focus.windowOrNil?.windowId, 2)
        }

        @Test func testFocusOverFloatingWindows() async {
            assertEquals(focus.windowOrNil, nil)
            workspaceForTest(name).floatingWindowsContainer.apply {
                TestWindow.new(id: 1, parent: $0, rect: Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100))
                assertEquals(
                    TestWindow.new(id: 2, parent: $0, rect: Rect(topLeftX: 10, topLeftY: 10, width: 100, height: 100))
                        .focusWindow(), true)
                TestWindow.new(id: 3, parent: $0, rect: Rect(topLeftX: 20, topLeftY: 20, width: 100, height: 100))
            }

            assertEquals(focus.windowOrNil?.windowId, 2)
            await Action.focusRight.run()
            assertEquals(focus.windowOrNil?.windowId, 3)
        }

        @Test func testFocusAlongTheContainerOrientation() async {
            workspaceForTest(name).rootTilingContainer.apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0)
            }

            assertEquals(focus.windowOrNil?.windowId, 1)
            await Action.focusRight.run()
            assertEquals(focus.windowOrNil?.windowId, 2)
        }

        @Test func testFocusAcrossTheContainerOrientation() async {
            workspaceForTest(name).apply {
                TestWindow.new(id: 1, parent: $0.rootTilingContainer)
                TestWindow.new(id: 2, parent: $0.rootTilingContainer)
                assertEquals($0.focusWorkspace(), true)
            }

            assertEquals(focus.windowOrNil?.windowId, 2)
            await Action.focusUp.run()
            assertEquals(focus.windowOrNil?.windowId, 2)
            await Action.focusDown.run()
            assertEquals(focus.windowOrNil?.windowId, 2)
        }

        @Test func testFocusFindMruLeaf() async {
            let workspace = workspaceForTest(name)
            var startWindow: Window!
            var window2: Window!
            var window3: Window!
            var unrelatedWindow: Window!
            workspace.rootTilingContainer.apply {
                startWindow = TestWindow.new(id: 1, parent: $0)
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                    TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                        window2 = TestWindow.new(id: 2, parent: $0)
                        unrelatedWindow = TestWindow.new(id: 5, parent: $0)
                    }
                    window3 = TestWindow.new(id: 3, parent: $0)
                }
            }

            assertEquals(workspace.mostRecentWindowRecursive?.windowId, 3)  // The latest bound
            _ = startWindow.focusWindow()
            await Action.focusRight.run()
            assertEquals(focus.windowOrNil?.windowId, 3)

            window2.markAsMostRecentChild()
            _ = startWindow.focusWindow()
            await Action.focusRight.run()
            assertEquals(focus.windowOrNil?.windowId, 2)

            window3.markAsMostRecentChild()
            unrelatedWindow.markAsMostRecentChild()
            _ = startWindow.focusWindow()
            await Action.focusRight.run()
            assertEquals(focus.windowOrNil?.windowId, 2)
        }

        @Test func testFocusOutsideOfTheContainer() async {
            workspaceForTest(name).rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0)
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                    assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
                }
            }

            await Action.focusLeft.run()
            assertEquals(focus.windowOrNil?.windowId, 1)
        }

        @Test func testFocusOutsideOfTheContainer2() async {
            workspaceForTest(name).rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0)
                TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                    assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
                }
            }

            await Action.focusLeft.run()
            assertEquals(focus.windowOrNil?.windowId, 1)
        }

    }
}
