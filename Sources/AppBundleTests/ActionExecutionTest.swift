import AppKit
import Common
import Testing

@testable import AppBundle

@MainActor final class TestDesktopSessionAdapter: DesktopSessionAdapter {
    var nativeFocus: Window? {
        get { TestApp.shared.focusedWindow }
        set { TestApp.shared.focusedWindow = newValue }
    }
    var failFocusRead = false
    var onRefreshWindows: (() throws -> Void)?
    var onValidatePopups: (() throws -> Bool)?
    private(set) var focusReads = 0
    private(set) var statusUpdates = 0
    private(set) var refreshes = 0

    func focusedWindow() throws -> Window? {
        focusReads += 1
        if failFocusRead { throw CancellationError() }
        return nativeFocus
    }
    func refreshWindows() throws {
        refreshes += 1
        try onRefreshWindows?()
    }
    func validatePopups() throws -> Bool { try onValidatePopups?() ?? false }
    func updateStatus() { statusUpdates += 1 }
}

extension CoreTests {
    @MainActor struct ActionExecutionTest {
        init() { setUpWorkspacesForTests() }

        private func recentFocusSequence() -> (TestWindow, TestWindow, TestWindow) {
            let workspace = focus.workspace
            let floating = TestWindow.new(id: 1, workspace: workspace, kind: .floating)
            let departing = TestWindow.new(id: 2, workspace: workspace)
            let other = TestWindow.new(id: 3, workspace: workspace)
            for window in [other, floating, departing] {
                DisplayLayoutState.shared.importNativeFocus(window)
            }
            return (floating, departing, other)
        }

        @Test(arguments: [false, true])
        func nativeCloseRestoresRecentFloat(macOSSelectedReplacement: Bool) async {
            let (floating, departing, other) = recentFocusSequence()
            let desktop = TestDesktopSessionAdapter()
            desktop.nativeFocus = macOSSelectedReplacement ? other : departing
            desktop.onRefreshWindows = { departing.layoutState.removeWindow(departing, remember: false) }
            let execution = ActionExecution(desktop: desktop)
            defer { execution.cancelRefresh() }
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(!departing.isRegistered)
            #expect(focus.windowOrNil === floating)
            #expect(desktop.nativeFocus === floating)
        }

        @Test(arguments: [false, true], [false, true])
        func nativeExclusionPreservesFullscreenFocusAndRecoversMinimize(
            fullscreen: Bool, macOSSelectedReplacement: Bool
        ) async {
            let (floating, departing, other) = recentFocusSequence()
            departing.isMacosFullscreenForTest = fullscreen
            departing.isMacosMinimizedForTest = !fullscreen
            let desktop = TestDesktopSessionAdapter()
            desktop.nativeFocus = macOSSelectedReplacement ? other : departing
            let execution = ActionExecution(desktop: desktop)
            defer { execution.cancelRefresh() }
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(departing.kind == (fullscreen ? .nativeFullscreen : .minimized))
            #expect(focus.windowOrNil === (fullscreen && macOSSelectedReplacement ? other : floating))
            #expect(desktop.nativeFocus === (fullscreen ? (macOSSelectedReplacement ? other : departing) : floating))
        }

        @Test func spaceChangeDoesNotApplyDepartureRecovery() async {
            let (_, departing, other) = recentFocusSequence()
            let desktop = TestDesktopSessionAdapter()
            desktop.nativeFocus = other
            desktop.onRefreshWindows = { departing.layoutState.removeWindow(departing, remember: true) }
            let execution = ActionExecution(desktop: desktop)
            defer { execution.cancelRefresh() }
            await execution.refresh(
                .globalObserver(NSWorkspace.activeSpaceDidChangeNotification.rawValue), assumeCancellable: false)
            #expect(desktop.nativeFocus === other)
            #expect(DisplayLayoutState.shared.takeFocusRecovery() == nil)
        }

        @Test func cancelledSpaceChangeDiscardsRecoveryBeforeLaterAXRefresh() async {
            let (_, departing, other) = recentFocusSequence()
            let desktop = TestDesktopSessionAdapter()
            desktop.nativeFocus = other
            desktop.onRefreshWindows = {
                departing.layoutState.removeWindow(departing, remember: true)
                throw CancellationError()
            }
            let execution = ActionExecution(desktop: desktop)
            defer { execution.cancelRefresh() }
            await execution.refresh(
                .globalObserver(NSWorkspace.activeSpaceDidChangeNotification.rawValue), assumeCancellable: true)
            desktop.onRefreshWindows = nil
            await execution.refresh(.ax(kAXFocusedWindowChangedNotification), assumeCancellable: false)
            #expect(desktop.nativeFocus === other)
            #expect(focus.windowOrNil === other)
        }

        @Test func fullscreenNativeFocusDiscardsEarlierDepartureRecovery() async {
            let (_, departing, other) = recentFocusSequence()
            departing.layoutState.removeWindow(departing, remember: true)
            other.isMacosFullscreenForTest = true
            let desktop = TestDesktopSessionAdapter()
            desktop.nativeFocus = other
            let execution = ActionExecution(desktop: desktop)
            defer { execution.cancelRefresh() }
            await execution.refresh(.ax(kAXFocusedWindowChangedNotification), assumeCancellable: false)
            #expect(desktop.nativeFocus === other)
            #expect(DisplayLayoutState.shared.takeFocusRecovery() == nil)
        }

        @Test func cancelledSpaceFocusReadDiscardsEarlierRecovery() async {
            let (_, departing, _) = recentFocusSequence()
            departing.layoutState.removeWindow(departing, remember: true)
            let desktop = TestDesktopSessionAdapter()
            desktop.failFocusRead = true
            let execution = ActionExecution(desktop: desktop)
            defer { execution.cancelRefresh() }
            await execution.refresh(
                .globalObserver(NSWorkspace.activeSpaceDidChangeNotification.rawValue), assumeCancellable: true)
            #expect(DisplayLayoutState.shared.takeFocusRecovery() == nil)
        }

        @Test func cancelledReconciliationRetainsFocusRecoveryForNextRefresh() async {
            let (floating, departing, other) = recentFocusSequence()
            let desktop = TestDesktopSessionAdapter()
            desktop.nativeFocus = other
            desktop.onRefreshWindows = {
                departing.layoutState.removeWindow(departing, remember: false)
                throw CancellationError()
            }
            let execution = ActionExecution(desktop: desktop)
            defer { execution.cancelRefresh() }
            await execution.refresh(.startup, assumeCancellable: true)
            desktop.onRefreshWindows = nil
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(focus.windowOrNil === floating)
            #expect(desktop.nativeFocus === floating)
        }

        @Test func actionAfterInterruptedRefreshUsesRecoveredFocus() async throws {
            let (floating, departing, other) = recentFocusSequence()
            let desktop = TestDesktopSessionAdapter()
            desktop.nativeFocus = other
            desktop.onRefreshWindows = {
                departing.layoutState.removeWindow(departing, remember: false)
                throw CancellationError()
            }
            let execution = ActionExecution(desktop: desktop)
            defer { execution.cancelRefresh() }
            await execution.refresh(.startup, assumeCancellable: true)
            desktop.onRefreshWindows = nil
            _ = try await execution.execute(.moveRight)
            #expect(focus.windowOrNil === floating)
            #expect(desktop.nativeFocus === floating)
        }

        @Test func closingUnfocusedWindowStillAcceptsNativeFocusChange() async {
            let (_, departing, other) = recentFocusSequence()
            _ = other.focusWindow()
            let desktop = TestDesktopSessionAdapter()
            desktop.nativeFocus = other
            desktop.onRefreshWindows = { departing.layoutState.removeWindow(departing, remember: false) }
            let execution = ActionExecution(desktop: desktop)
            defer { execution.cancelRefresh() }
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(focus.windowOrNil === other && desktop.nativeFocus === other)
        }

        @Test func refreshAcceptsNativeFocusChangesWhilePreviousWindowRemainsAvailable() async {
            let (_, _, other) = recentFocusSequence()
            let desktop = TestDesktopSessionAdapter()
            desktop.nativeFocus = other
            let execution = ActionExecution(desktop: desktop)
            defer { execution.cancelRefresh() }
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(focus.windowOrNil === other)
        }

        @Test func closingLastWindowKeepsEmptyScreenSelected() async {
            let source = focus.workspace
            let departing = TestWindow.new(id: 1, workspace: source)
            let side = TestMonitor(displayId: "side", name: "Side", x: 1920)
            unsafe testMonitors = monitorInfos + [side]
            source.state.reconcileMonitors(monitorInfos)
            let other = TestWindow.new(id: 2, workspace: side.activeWorkspace)
            source.state.importNativeFocus(departing)
            let desktop = TestDesktopSessionAdapter()
            desktop.nativeFocus = other
            desktop.onRefreshWindows = { source.state.removeWindow(departing, remember: false) }
            let execution = ActionExecution(desktop: desktop)
            defer { execution.cancelRefresh() }
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(focus.workspace === source && focus.windowOrNil == nil)
            // An unchanged automatic native selection must not steal the empty screen next refresh.
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(focus.workspace === source && focus.windowOrNil == nil)
        }

        @Test func importsNativeFocusThenAppliesFramesAndNativeFocus() async throws {
            let root = focus.workspace
            let left = TestWindow.new(id: 1, workspace: root)
            let right = TestWindow.new(id: 2, workspace: root)
            _ = right.focusWindow()
            let desktop = TestDesktopSessionAdapter()
            desktop.nativeFocus = left
            let execution = ActionExecution(desktop: desktop)
            defer { execution.cancelRefresh() }
            let result = try await execution.execute(.focusRight)
            #expect(result.exitCode == .succ)
            #expect(focus.windowOrNil === right)
            #expect(TestApp.shared.focusedWindow === right)
            let leftRect = try #require(await left.getAxRect(.nonCancellable))
            let rightRect = try #require(await right.getAxRect(.nonCancellable))
            #expect(leftRect.maxX + CGFloat(config.gap) == rightRect.minX)
            #expect(desktop.statusUpdates == 1)
        }

        @Test func failedActionStillLaysOutAndPausedActionsDoNothing() async throws {
            let window = TestWindow.new(id: 1, workspace: focus.workspace)
            let desktop = TestDesktopSessionAdapter()
            desktop.nativeFocus = window
            let execution = ActionExecution(desktop: desktop)
            defer { execution.cancelRefresh() }
            let failed = try await execution.execute(.grow)
            #expect(failed.exitCode == .fail)
            let rect = try #require(await window.getAxRect(.nonCancellable))
            #expect(rect.width > 0)
            ConfigurationApplication.shared.setEnabled(false)
            let reads = desktop.focusReads
            let paused = try await execution.execute(.close)
            #expect(paused.exitCode == .fail)
            #expect(desktop.focusReads == reads)
            #expect(window.isRegistered)
            let enabled = try await execution.execute(.toggleTiling, from: .menu)
            #expect(enabled.exitCode == .succ)
            #expect(ConfigurationApplication.shared.isEnabled)
        }

        @Test func overlappingMenuTogglesPreserveTheSecondTransition() async throws {
            let shortcuts = RecordingShortcutRegistrar()
            let application = ConfigurationApplication(defaults: defaultConfig, shortcuts: shortcuts)
            ConfigurationApplication.shared = application
            application.setEnabled(false)
            let window = TestWindow.new(
                id: 1, workspace: focus.workspace, kind: .floating,
                rect: Rect(topLeftX: 100, topLeftY: 100, width: 400, height: 300))
            let started = AwaitableOneTimeBroadcastLatch()
            let resumeRead = AwaitableOneTimeBroadcastLatch()
            window.beforeNextSizeRead = {
                await started.signalToAll()
                try await resumeRead.await()
            }
            let execution = ActionExecution(desktop: TestDesktopSessionAdapter())
            defer { execution.cancelRefresh() }
            let first = Task { try await execution.execute(.toggleTiling, from: .menu) }
            defer { first.cancel() }
            try await started.await()
            let second = try await execution.execute(.toggleTiling, from: .menu)
            #expect(second.exitCode == .succ)
            #expect(!application.isEnabled)
            #expect(shortcuts.bindings.isEmpty)
            await resumeRead.signalToAll()
            let firstResult = try await first.value
            #expect(firstResult.exitCode == .succ)
            #expect(!application.isEnabled)
            #expect(shortcuts.bindings.isEmpty)
            #expect(window.lastFloatingSize == CGSize(width: 400, height: 300))
        }

        @Test func movesAcrossDisplaysAndWritesDestinationFrame() async throws {
            let side = TestMonitor(displayId: "side", name: "Side", x: 1920)
            unsafe testMonitors = monitorInfos + [side]
            DisplayLayoutState.shared.reconcileMonitors(monitorInfos)
            let window = TestWindow.new(id: 1, workspace: focus.workspace)
            let desktop = TestDesktopSessionAdapter()
            desktop.nativeFocus = window
            let execution = ActionExecution(desktop: desktop)
            defer { execution.cancelRefresh() }
            let result = try await execution.execute(.moveToNextMonitor)
            #expect(result.exitCode == .succ)
            #expect(focus.windowOrNil === window)
            #expect(focus.workspace === side.activeWorkspace)
            let rect = try #require(await window.getAxRect(.nonCancellable))
            #expect(rect.minX == side.rect.minX + CGFloat(config.gap))
            #expect(rect.width == side.visibleRectPaddedByOuterGaps.width)
        }

        @Test func actionCancelsAnInFlightBackgroundRefresh() async throws {
            let root = focus.workspace
            let left = TestWindow.new(id: 1, workspace: root)
            let right = TestWindow.new(id: 2, workspace: root)
            TestApp.shared.focusedWindow = left
            let desktop = SuspendingDesktopSessionAdapter()
            let execution = ActionExecution(desktop: desktop)
            defer { execution.cancelRefresh() }
            execution.scheduleRefresh(.startup)
            try await desktop.started.await()
            let result = try await execution.execute(.focusRight)
            try await desktop.cancelled.await()
            #expect(result.exitCode == .succ)
            #expect(focus.windowOrNil === right)
            #expect(TestApp.shared.focusedWindow === right)
        }

        @Test func cancelledFocusReadDoesNotApplyTheAction() async throws {
            let window = TestWindow.new(id: 1, workspace: focus.workspace)
            let desktop = TestDesktopSessionAdapter()
            desktop.failFocusRead = true
            let execution = ActionExecution(desktop: desktop)
            do {
                _ = try await execution.execute(.close)
                Issue.record("Expected cancellation")
            } catch is CancellationError {}
            #expect(window.isRegistered)
            #expect(desktop.statusUpdates == 0)
        }

        @Test func reclassifiedPopupImportsNativeFocusInSameRefresh() async {
            let workspace = focus.workspace
            let existing = TestWindow.new(id: 1, workspace: workspace)
            _ = existing.focusWindow()
            let promoted = TestWindow.new(id: 2, workspace: workspace, kind: .popup)
            let desktop = TestDesktopSessionAdapter()
            desktop.nativeFocus = promoted
            desktop.onValidatePopups = {
                workspace.state.place(promoted, on: workspace, kind: .tiled)
                return true
            }
            let execution = ActionExecution(desktop: desktop)
            defer { execution.cancelRefresh() }
            await execution.refresh(.startup, assumeCancellable: false)
            #expect(promoted.kind == .tiled)
            #expect(focus.windowOrNil === promoted)
        }

        @Test func backgroundRefreshScheduledDuringActiveSessionWaitsUntilSessionFinishes() async throws {
            let workspace = focus.workspace
            let window = TestWindow.new(
                id: 1, workspace: workspace, kind: .floating,
                rect: Rect(topLeftX: 100, topLeftY: 100, width: 400, height: 300))
            _ = window.focusWindow()
            let started = AwaitableOneTimeBroadcastLatch()
            let resumeRead = AwaitableOneTimeBroadcastLatch()
            window.beforeNextSizeRead = {
                await started.signalToAll()
                try await resumeRead.await()
            }
            let desktop = TestDesktopSessionAdapter()
            desktop.nativeFocus = window
            let refreshed = AwaitableOneTimeBroadcastLatch()
            desktop.onRefreshWindows = {
                Task { await refreshed.signalToAll() }
            }
            let execution = ActionExecution(desktop: desktop)
            defer { execution.cancelRefresh() }
            let actionTask = Task { try await execution.execute(.toggleFloating) }
            defer { actionTask.cancel() }
            try await started.await()
            execution.scheduleRefresh(.startup)
            await Task.yield()
            #expect(desktop.refreshes == 0)
            await resumeRead.signalToAll()
            let result = try await actionTask.value
            #expect(result.exitCode == .succ)
            try await refreshed.await()
            #expect(desktop.refreshes == 1)
        }

        @Test func overlappingShortcutsApplyOnlyLatestSessionFocus() async throws {
            let workspace = focus.workspace
            let left = TestWindow.new(id: 1, workspace: workspace)
            let middle = TestWindow.new(id: 2, workspace: workspace)
            let right = TestWindow.new(id: 3, workspace: workspace)
            let float = TestWindow.new(
                id: 4, workspace: workspace, kind: .floating,
                rect: Rect(topLeftX: 80, topLeftY: 80, width: 320, height: 220))
            _ = middle.focusWindow()
            let desktop = TestDesktopSessionAdapter()
            desktop.nativeFocus = middle
            let inFirstLayout = AwaitableOneTimeBroadcastLatch()
            let releaseFirstLayout = AwaitableOneTimeBroadcastLatch()
            float.beforeNextRectRead = {
                await inFirstLayout.signalToAll()
                try await releaseFirstLayout.await()
            }
            let execution = ActionExecution(desktop: desktop)
            defer { execution.cancelRefresh() }

            // First shortcut moves logical focus to `left`, then suspends inside layoutWorkspaces().
            let first = Task { try await execution.execute(.focusLeft) }
            defer { first.cancel() }
            try await inFirstLayout.await()
            #expect(focus.windowOrNil === left)

            // Second shortcut runs while first is suspended and focuses `right` (`left` -> `middle` -> `right`).
            desktop.nativeFocus = left
            _ = try await execution.execute(.focusRight)
            desktop.nativeFocus = middle
            _ = try await execution.execute(.focusDown)
            #expect(focus.windowOrNil === right)
            #expect(desktop.nativeFocus === right)

            // Resuming the older session must not clobber native focus back to `left`.
            await releaseFirstLayout.signalToAll()
            _ = try await first.value
            #expect(focus.windowOrNil === right)
            #expect(desktop.nativeFocus === right)
        }

        @Test func optimisticRefreshDeferredDuringActiveSessionPreservesOptimisticFlag() async throws {
            let workspace = focus.workspace
            let window = TestWindow.new(
                id: 1, workspace: workspace, kind: .floating,
                rect: Rect(topLeftX: 100, topLeftY: 100, width: 400, height: 300))
            let tile = TestWindow.new(id: 2, workspace: workspace)
            _ = window.focusWindow()
            let started = AwaitableOneTimeBroadcastLatch()
            let resumeRead = AwaitableOneTimeBroadcastLatch()
            window.beforeNextSizeRead = {
                await started.signalToAll()
                try await resumeRead.await()
            }
            let desktop = TestDesktopSessionAdapter()
            desktop.nativeFocus = window
            var preLayoutFrameObservedDuringRefresh: Rect?
            let refreshed = AwaitableOneTimeBroadcastLatch()
            desktop.onRefreshWindows = {
                // Optimistic pre-layout runs before refreshWindows(), so `tile` already has its frame.
                preLayoutFrameObservedDuringRefresh = tile.lastAppliedLayoutPhysicalRect
                Task { await refreshed.signalToAll() }
            }
            let execution = ActionExecution(desktop: desktop)
            defer { execution.cancelRefresh() }

            let session = Task { try await execution.execute(.toggleFloating) }
            defer { session.cancel() }
            try await started.await()
            // Clear tile's applied rect after scheduling an optimistic refresh followed by a non-optimistic one.
            execution.scheduleRefresh(
                .globalObserver(NSWorkspace.didActivateApplicationNotification.rawValue),
                optimisticallyPreLayoutWorkspaces: true)
            execution.scheduleRefresh(
                .ax(kAXFocusedWindowChangedNotification), optimisticallyPreLayoutWorkspaces: false)
            #expect(desktop.refreshes == 0)

            await resumeRead.signalToAll()
            _ = try await session.value
            // Note: runSession's trailing scheduleRefresh coalesces with any queued optimistic flag.
            try await refreshed.await()
            #expect(preLayoutFrameObservedDuringRefresh != nil)
        }

        @Test func outOfOrderSizeCallbacksCannotCorruptNewerLayoutOrRoundingBaseline() async throws {
            let workspace = focus.workspace
            let a = TestWindow.new(id: 1, workspace: workspace)
            let b = TestWindow.new(id: 2, workspace: workspace)
            try await workspace.layoutWorkspace()
            let initialRect = try #require(workspace.tiledFrames[1])
            let roundedInitial = CGSize(width: initialRect.width - 10, height: initialRect.height - 6)
            #expect(!a.observeAppliedSize(requested: initialRect.size, actual: roundedInitial))
            #expect(a.gestureBaselineRect?.size == roundedInitial)

            // Resize split so `a` gets a new requested width, then deliver a stale callback from `initialRect`.
            workspace.layout.resize(1, axis: .h, by: 140, in: workspace.layoutRect, gap: CGFloat(config.gap))
            try await workspace.layoutWorkspace()
            let resizedRect = try #require(workspace.tiledFrames[1])
            #expect(!a.observeAppliedSize(requested: initialRect.size, actual: CGSize(width: 900, height: 900)))
            #expect(a.gestureBaselineRect?.size == resizedRect.size)
            #expect(a.minimumSize == BinaryLayout.baseline)

            // Dragging `a` with its new size swaps cleanly with `b` rather than resizing.
            var moved = resizedRect
            moved.topLeftX += 25
            let target = try #require(workspace.tiledFrames[b.windowId])
            let mouse = TestPointerDriver(state: workspace.state)
            defer { mouse.cancel() }
            mouse.observe(a, frame: moved)
            mouse.drag(at: target.center, on: workspace)
            #expect(workspace.layout.windowIds == [2, 1])
        }
    }
}

@MainActor private final class SuspendingDesktopSessionAdapter: DesktopSessionAdapter {
    let started = AwaitableOneTimeBroadcastLatch()
    let cancelled = AwaitableOneTimeBroadcastLatch()
    private let pending = AwaitableOneTimeBroadcastLatch()
    private var firstRead = true

    func focusedWindow() async throws -> Window? {
        if firstRead {
            firstRead = false
            await started.signalToAll()
            do { try await pending.await() } catch {
                await cancelled.signalToAll()
                throw error
            }
        }
        return TestApp.shared.focusedWindow
    }
    func refreshWindows() {}
    func validatePopups() -> Bool { false }
    func updateStatus() {}
}
