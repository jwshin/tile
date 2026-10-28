import AppKit
import Testing

@testable import AppBundle

extension CoreTests {
    @MainActor struct SleepWakeTest {
        init() {
            setUpWorkspacesForTests()
            let pointer = TestPointerAdapter()
            pointer.isButtonDown = false
            DisplayLayoutState.shared = DisplayLayoutState(monitors: monitorInfos, pointer: pointer)
        }
        private let main = TestMonitor(displayId: "test-main", name: "Main", x: 0, isMain: true)
        private let side = TestMonitor(displayId: "side", name: "Side", x: 1920)

        @Test func sleepingAndPartialWakeDoNotDestroyLayoutsOrRestoration() {
            let state = DisplayLayoutState.shared
            state.reconcileMonitors([main, side])
            let source = state.workspace(for: side)
            let window = TestWindow.new(id: 1, workspace: source)
            let absent = TestWindow.new(id: 2, workspace: source)
            state.removeWindow(absent, remember: true)
            let tree = source.layout
            state.beginDisplaySleep(.system)
            state.reconcileMonitors([main])
            #expect(window.workspace === source)
            #expect(source.layout == tree)
            state.beginDisplayWake(.system, at: 0)
            #expect(!state.advanceDisplayRecovery([main], at: 0))
            #expect(!state.advanceDisplayRecovery([main], at: 3))
            state.reconcileMonitors([main])
            #expect(window.workspace === source)
            #expect(!state.advanceDisplayRecovery([main, side], at: 4))
            #expect(state.advanceDisplayRecovery([main, side], at: 5))
            state.reconcileMonitors([main, side])
            #expect(state.workspace(for: side) === source)
            let returned = TestWindow.new(id: 2, workspace: source)
            #expect(state.restoreWindow(newlyDetectedWindow: returned))
        }

        @Test func unknownFullscreenRetainsExclusionAndNeverWritesTileFrame() async throws {
            let state = DisplayLayoutState.shared
            let window = TestWindow.new(
                id: 1, workspace: state.mainWorkspace,
                rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080))
            window.isMacosFullscreenForTest = true
            let desktop = TestDesktopSessionAdapter()
            desktop.nativeFocus = window
            let execution = ActionExecution(desktop: desktop)
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(window.kind == .nativeFullscreen)
            window.isMacosFullscreenForTest = nil
            await execution.refresh(.ax("WakeObservation"), assumeCancellable: false)
            #expect(window.kind == .nativeFullscreen)
            #expect(state.mainWorkspace.layout.windowIds.isEmpty)
            #expect(try await window.getAxRect(.nonCancellable)?.width == 1920)
            window.isMacosFullscreenForTest = false
            await execution.refresh(.ax("ConfirmedExit"), assumeCancellable: false)
            #expect(window.kind == .tiled)
        }

        @Test func optimisticLayoutDoesNotResizeWindowThatJustEnteredFullscreen() async throws {
            let state = DisplayLayoutState.shared
            let window = TestWindow.new(
                id: 1, workspace: state.mainWorkspace,
                rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080))
            TestWindow.new(id: 2, workspace: state.mainWorkspace)
            window.isMacosFullscreenForTest = true
            let desktop = TestDesktopSessionAdapter()
            desktop.nativeFocus = window
            await ActionExecution(desktop: desktop).refresh(
                .startup, assumeCancellable: false,
                optimisticallyPreLayoutWorkspaces: true)
            #expect(window.kind == .nativeFullscreen)
            #expect(try await window.getAxRect(.nonCancellable)?.width == 1920)
        }

        @Test func missingMonitorMigratesOnlyAfterGraceAndReconnectStillStartsEmpty() {
            let state = DisplayLayoutState.shared
            state.reconcileMonitors([main, side])
            let window = TestWindow.new(id: 1, workspace: state.workspace(for: side))
            state.beginDisplaySleep(.system)
            state.beginDisplayWake(.system, at: 100)
            #expect(!state.advanceDisplayRecovery([main], at: 100))
            #expect(!state.advanceDisplayRecovery([main], at: 109))
            #expect(state.advanceDisplayRecovery([main], at: 110))
            state.reconcileMonitors([main])
            #expect(window.workspace === state.mainWorkspace)
            state.reconcileMonitors([main, side])
            #expect(state.workspace(for: side).isEffectivelyEmpty)
        }

        @Test func nestedPowerEventsAndChangingGeometryKeepProtectionUntilStable() {
            let state = DisplayLayoutState.shared
            let window = TestWindow.new(id: 1, workspace: state.mainWorkspace)
            window.minimumSize = CGSize(width: 1000, height: 700)
            state.beginDisplaySleep(.system)
            state.beginDisplaySleep(.screens)
            state.beginDisplayWake(.system, at: 0)
            #expect(!state.advanceDisplayRecovery([main], at: 20))
            state.beginDisplayWake(.screens, at: 21)
            let small = TestMonitor(displayId: "test-main", name: "Main", x: 0, isMain: true, width: 800, height: 600)
            #expect(!state.advanceDisplayRecovery([small], at: 21))
            state.reconcileMonitors([small])
            #expect(window.kind == .tiled)
            #expect(!state.advanceDisplayRecovery([small], at: 23))
            #expect(!state.advanceDisplayRecovery([main], at: 23.5))
            #expect(!state.advanceDisplayRecovery([main], at: 24))
            #expect(state.advanceDisplayRecovery([main], at: 24.5))
            #expect(window.kind == .tiled)
        }

        @Test func noDisplaysRemainProtectedPastDeadlineAndNextEventCanResume() {
            let state = DisplayLayoutState.shared
            state.beginDisplaySleep(.screens)
            state.beginDisplayWake(.screens, at: 0)
            #expect(!state.advanceDisplayRecovery([], at: 11))
            #expect(!state.displayRecovery.shouldPoll(at: 11))
            #expect(!state.advanceDisplayRecovery([main], at: 20))
            #expect(state.displayRecovery.shouldPoll(at: 20))
            #expect(state.advanceDisplayRecovery([main], at: 21))
        }

        @Test func sleepCancelsQueuedFramesAndBlocksRefreshAndCommands() async throws {
            let state = DisplayLayoutState.shared
            let window = TestWindow.new(
                id: 1, workspace: state.mainWorkspace,
                rect: Rect(topLeftX: 20, topLeftY: 20, width: 400, height: 300))
            window.deferFrameWrites = true
            try await state.mainWorkspace.layoutWorkspace()
            let desktop = TestDesktopSessionAdapter()
            var now: TimeInterval = 0
            let execution = ActionExecution(desktop: desktop, now: { now }, automaticallyPollRecovery: false)
            execution.displayWillSleep(.system)
            window.flushPendingFrame()
            #expect(try await window.getAxRect(.nonCancellable)?.width == 400)
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(desktop.focusReads == 0 && desktop.refreshes == 0)
            let tree = state.mainWorkspace.layout
            let result = try await execution.execute(.toggleFloating)
            #expect(result.exitCode == .fail)
            #expect(state.mainWorkspace.layout == tree)
            execution.displayDidWake(.system)
            now = 1
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(!state.isRecoveringDisplays)
            #expect(desktop.refreshes == 1)
            execution.cancelRefresh()
        }

        @Test func refreshInterruptedBySleepCannotContinueReconciliation() async {
            let state = DisplayLayoutState.shared
            let window = TestWindow.new(id: 1, workspace: state.mainWorkspace)
            let desktop = TestDesktopSessionAdapter()
            let execution = ActionExecution(desktop: desktop, automaticallyPollRecovery: false)
            desktop.onRefreshWindows = { execution.displayWillSleep(.system) }
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(state.isRecoveringDisplays)
            #expect(window.kind == .tiled)
            #expect(desktop.statusUpdates == 0)
        }

        @Test func staleRefreshIsRejectedEvenAfterWakeRecoveryFinishes() async {
            let state = DisplayLayoutState.shared
            let desktop = TestDesktopSessionAdapter()
            let execution = ActionExecution(desktop: desktop, automaticallyPollRecovery: false)
            desktop.onRefreshWindows = {
                execution.displayWillSleep(.system)
                state.beginDisplayWake(.system, at: 0)
                state.advanceDisplayRecovery([main], at: 0)
                #expect(state.advanceDisplayRecovery([main], at: 1))
            }
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(!state.isRecoveringDisplays)
            #expect(desktop.statusUpdates == 0)
        }

        @Test func menuCanDisableAndEnableDuringRecoveryWithoutReadingOrWritingWindows() async throws {
            let desktop = TestDesktopSessionAdapter()
            let execution = ActionExecution(desktop: desktop, automaticallyPollRecovery: false)
            execution.displayWillSleep(.screens)
            for enabled in [false, true] {
                let result = try await execution.execute(.toggleTiling, from: .menu)
                #expect(result.exitCode == .succ)
                #expect(ConfigurationApplication.shared.isEnabled == enabled)
            }
            #expect(desktop.focusReads == 0 && desktop.refreshes == 0)
            #expect(DisplayLayoutState.shared.isRecoveringDisplays)
        }

        @Test func wakePollingResumesWithoutAnyFurtherNativeNotification() async throws {
            let desktop = TestDesktopSessionAdapter()
            var now: TimeInterval = 0
            let execution = ActionExecution(desktop: desktop, now: { now })
            defer { execution.displayWillSleep(.system) }
            execution.displayWillSleep(.system)
            execution.displayDidWake(.system)
            now = 1.25
            let deadline = ContinuousClock.now + .seconds(2)
            while desktop.refreshes == 0 && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(desktop.refreshes == 1)
            #expect(!DisplayLayoutState.shared.isRecoveringDisplays)
        }

        @Test func layoutUsesCurrentAllocationAfterSuspendingFullscreenRead() async throws {
            let workspace = DisplayLayoutState.shared.mainWorkspace
            let window = TestWindow.new(id: 1, workspace: workspace)
            TestWindow.new(id: 2, workspace: workspace)
            window.beforeNextFullscreenRead = {
                workspace.layout.resize(1, by: 100, in: workspace.layoutRect, gap: 8)
            }
            try await workspace.layoutWorkspace()
            #expect(try await window.getAxRect(.nonCancellable)?.size == workspace.tiledFrames[1]?.size)
        }

        @Test func queuedFrameRechecksFullscreenBeforeEachWrite() throws {
            for observation: Bool? in [true, nil, false] {
                var writes: [String] = []
                var current: Bool? = false
                _ = try NativeFrameWriter.apply(
                    position: .zero, size: CGSize(width: 500, height: 400),
                    fullscreen: { current }, checkCancellation: {},
                    writeSize: { _ in
                        writes.append("size")
                        current = observation
                        return true
                    },
                    writePosition: { _ in
                        writes.append("position")
                        return true
                    }, readSize: { .zero })
                #expect(writes == (observation == false ? ["size", "position", "size"] : ["size"]))
            }
            for observation: Bool? in [true, nil] {
                var writes = 0
                _ = try NativeFrameWriter.apply(
                    position: .zero, size: .zero, fullscreen: { observation },
                    checkCancellation: {},
                    writeSize: { _ in
                        writes += 1
                        return true
                    },
                    writePosition: { _ in
                        writes += 1
                        return true
                    }, readSize: { .zero })
                #expect(writes == 0)
            }
        }

        @Test func cancellationDuringFullscreenReadPreventsWrite() {
            var cancelled = false
            var writes = 0
            #expect(throws: CancellationError.self) {
                try NativeFrameWriter.apply(
                    position: .zero, size: .zero,
                    fullscreen: {
                        cancelled = true
                        return false
                    },
                    checkCancellation: { if cancelled { throw CancellationError() } },
                    writeSize: { _ in
                        writes += 1
                        return true
                    },
                    writePosition: { _ in
                        writes += 1
                        return true
                    }, readSize: { .zero })
            }
            #expect(writes == 0)
        }
    }
}
