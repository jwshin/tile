import Common
import Testing

@testable import AppBundle

extension CoreTests {
    @MainActor struct DisplayLayoutStateTest {
        init() { setUpWorkspacesForTests() }
        private let main = TestMonitor(displayId: "main", name: "Main", x: 0, isMain: true)
        private let side = TestMonitor(displayId: "side", name: "Side", x: 1920)

        @Test func ownersDoNotShareLayoutsFocusOrWindowIdentity() {
            let first = DisplayLayoutState(monitors: [main, side])
            let second = DisplayLayoutState(monitors: [main, side])
            let firstWindow = TestWindow.new(id: 1, parent: first.workspace(for: side).rootTilingContainer)
            let secondWindow = TestWindow.new(id: 1, parent: second.mainWorkspace.rootTilingContainer)
            _ = firstWindow.focusWindow()
            #expect(first.focus.windowOrNil === firstWindow)
            #expect(second.focus.windowOrNil === secondWindow)
            #expect(first.window(for: 1) === firstWindow)
            #expect(second.window(for: 1) === secondWindow)
            #expect(second.workspace(for: side).isEffectivelyEmpty)
            first.reconcileMonitors([main])
            #expect(first.workspaces.count == 1)
            #expect(second.workspaces.count == 2)
        }

        @Test func popupAndMinimizedWindowsUseTheirContainerOwner() {
            let first = DisplayLayoutState(monitors: [main])
            let second = DisplayLayoutState(monitors: [main])
            let firstPopup = TestWindow.new(id: 1, parent: first.popupWindows)
            let secondPopup = TestWindow.new(id: 1, parent: second.popupWindows)
            let firstMinimized = TestWindow.new(id: 2, parent: first.minimizedWindows)
            let secondMinimized = TestWindow.new(id: 2, parent: second.minimizedWindows)
            #expect(first.window(for: 1) === firstPopup)
            #expect(second.window(for: 1) === secondPopup)
            #expect(first.window(for: 2) === firstMinimized)
            #expect(second.window(for: 2) === secondMinimized)
            #expect(DisplayLayoutState.shared.allWindows.isEmpty)
        }

        @Test func restorationIsInvalidatedBeforeMutationCanSuspend() async throws {
            let state = DisplayLayoutState(monitors: [main, side])
            let old = TestWindow.new(id: 1, parent: state.workspace(for: side).rootTilingContainer)
            state.removeWindow(old, remember: true)
            try await state.changeLayout {
                await Task.yield()
                let returned = TestWindow.new(id: 1, parent: state.mainWorkspace.rootTilingContainer)
                let restored = try await state.restoreWindow(newlyDetectedWindow: returned)
                #expect(!restored)
                #expect(returned.nodeWorkspace === state.mainWorkspace)
            }
        }

        @Test func returningWindowsRestoreOrderWeightsAndDisplayMembership() async throws {
            let state = DisplayLayoutState(monitors: [main, side])
            let root = state.workspace(for: side).rootTilingContainer
            root.changeOrientation(.v)
            let a = TestWindow.new(id: 1, parent: root, adaptiveWeight: 3)
            let b = TestWindow.new(id: 2, parent: root, adaptiveWeight: 1)
            state.removeWindow(a, remember: true)
            state.removeWindow(b, remember: true)
            state.normalize()
            #expect(state.allWindows.isEmpty)
            // macOS can return windows in a different order after unlocking.
            let returnedB = TestWindow.new(id: 2, parent: state.mainWorkspace.rootTilingContainer)
            #expect(try await state.restoreWindow(newlyDetectedWindow: returnedB))
            let returnedA = TestWindow.new(id: 1, parent: state.mainWorkspace.rootTilingContainer)
            #expect(try await state.restoreWindow(newlyDetectedWindow: returnedA))
            let restored = state.workspace(for: side).rootTilingContainer
            #expect(restored.children == [returnedA, returnedB])
            #expect(restored.orientation == .v)
            #expect(returnedA.vWeight == 3 && returnedB.vWeight == 1)
            #expect(state.mainWorkspace.isEffectivelyEmpty)
        }

        @Test func disconnectWhileWindowsAreMissingInvalidatesObsoleteSnapshot() async throws {
            let state = DisplayLayoutState(monitors: [main, side])
            let old = TestWindow.new(id: 1, parent: state.workspace(for: side).rootTilingContainer)
            state.removeWindow(old, remember: true)
            state.reconcileMonitors([main])
            let returned = TestWindow.new(id: 1, parent: state.mainWorkspace.rootTilingContainer)
            #expect(try await !state.restoreWindow(newlyDetectedWindow: returned))
            #expect(returned.nodeWorkspace === state.mainWorkspace)
            state.reconcileMonitors([main, side])
            #expect(state.workspace(for: side).isEffectivelyEmpty)
        }

        @Test func layoutMutationInvalidatesSnapshotButEmptyDisplaySnapshotDoesNot() async throws {
            let state = DisplayLayoutState(monitors: [main, side])
            let first = TestWindow.new(id: 1, parent: state.workspace(for: side).rootTilingContainer)
            state.removeWindow(first, remember: true)
            state.reconcileMonitors([])
            let returned = TestWindow.new(id: 1, parent: state.mainWorkspace.rootTilingContainer)
            #expect(try await state.restoreWindow(newlyDetectedWindow: returned))
            state.removeWindow(returned, remember: true)
            await state.changeLayout { state.mainWorkspace.rootTilingContainer.changeOrientation(.v) }
            let afterEdit = TestWindow.new(id: 1, parent: state.mainWorkspace.rootTilingContainer)
            #expect(try await !state.restoreWindow(newlyDetectedWindow: afterEdit))
        }

        @Test func sharedRefreshHandlesHiddenFullscreenAndMinimizedWindows() async throws {
            let state = DisplayLayoutState.shared
            let window = TestWindow.new(id: 1, parent: state.mainWorkspace.rootTilingContainer)
            let execution = ActionExecution(desktop: TestDesktopSessionAdapter())
            TestApp.shared.isHidden = true
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(window.parent === state.mainWorkspace.macOsNativeHiddenAppsWindowsContainer)
            TestApp.shared.isHidden = false
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(window.parent === state.mainWorkspace.rootTilingContainer)
            window.isMacosFullscreenForTest = true
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(window.parent === state.mainWorkspace.macOsNativeFullscreenWindowsContainer)
            window.isMacosFullscreenForTest = false
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(window.parent === state.mainWorkspace.rootTilingContainer)
            window.isMacosMinimizedForTest = true
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(window.parent === state.minimizedWindows)
            #expect(state.window(for: window.windowId) === window)
            window.isMacosMinimizedForTest = false
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(window.parent === state.mainWorkspace.rootTilingContainer)
        }
    }
}
