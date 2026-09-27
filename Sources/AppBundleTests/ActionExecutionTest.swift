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
    private(set) var focusReads = 0
    private(set) var statusUpdates = 0
    private(set) var refreshes = 0

    func focusedWindow() throws -> Window? {
        focusReads += 1
        if failFocusRead { throw CancellationError() }
        return nativeFocus
    }
    func refreshWindows() { refreshes += 1 }
    func validatePopups() {}
    func updateStatus() { statusUpdates += 1 }
}

extension CoreTests {
    @MainActor struct ActionExecutionTest {
        init() { setUpWorkspacesForTests() }

        @Test func importsNativeFocusThenAppliesFramesAndNativeFocus() async throws {
            let root = focus.workspace.rootTilingContainer
            let left = TestWindow.new(id: 1, parent: root)
            let right = TestWindow.new(id: 2, parent: root)
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
            let window = TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer)
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
            #expect(window.parent != nil)
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
                id: 1, parent: focus.workspace.floatingWindowsContainer,
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
            let window = TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer)
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
            let root = focus.workspace.rootTilingContainer
            let left = TestWindow.new(id: 1, parent: root)
            let right = TestWindow.new(id: 2, parent: root)
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
            let window = TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer)
            let desktop = TestDesktopSessionAdapter()
            desktop.failFocusRead = true
            let execution = ActionExecution(desktop: desktop)
            do {
                _ = try await execution.execute(.close)
                Issue.record("Expected cancellation")
            } catch is CancellationError {}
            #expect(window.parent != nil)
            #expect(desktop.statusUpdates == 0)
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
    func validatePopups() {}
    func updateStatus() {}
}
