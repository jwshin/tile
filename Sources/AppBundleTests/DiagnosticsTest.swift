import AppKit
import Common
import Testing

@testable import AppBundle

extension CoreTests {
    @MainActor struct DiagnosticsTest {
        init() { setUpWorkspacesForTests() }

        @Test func preservesMembershipFocusRestorationAndGesture() {
            let pointer = TestPointerAdapter()
            let state = DisplayLayoutState(monitors: monitorInfos, pointer: pointer)
            let workspace = state.mainWorkspace
            let tiled = TestWindow.new(id: 1, workspace: workspace)
            _ = TestWindow.new(id: 2, workspace: workspace, kind: .floating)
            _ = TestWindow.new(id: 3, workspace: workspace, kind: .hidden)
            _ = TestWindow.new(id: 4, workspace: workspace, kind: .nativeFullscreen)
            _ = TestWindow.new(id: 5, workspace: workspace, kind: .minimized)
            _ = TestWindow.new(id: 6, workspace: workspace, kind: .popup)
            let missing = TestWindow.new(id: 7, workspace: workspace)
            state.setFocus(to: LiveFocus(windowOrNil: tiled, workspace: workspace))
            state.removeWindow(missing, remember: true)
            pointer.isButtonDown = true
            let frame = workspace.tiledFrames[1]!
            state.updatePointer(tiled, frame: frame, at: frame.center, on: workspace)
            let before = workspace.layout
            let focused = state.focus.windowOrNil
            let manipulated = state.manipulatedWindow
            #expect(manipulated === tiled)
            let report = state.diagnosticReport
            #expect(report.contains("kind=tiled"))
            #expect(report.contains("kind=floating"))
            #expect(report.contains("kind=hidden"))
            #expect(report.contains("kind=nativeFullscreen"))
            #expect(report.contains("kind=minimized"))
            #expect(report.contains("kind=popup"))
            #expect(report.contains("window=1 source=test-main kind=tiled resizing=false"))
            #expect(workspace.layout == before)
            #expect(state.allWindows.map(\.windowId) == [1, 2, 3, 4, 5, 6])
            #expect(state.focus.windowOrNil === focused)
            #expect(state.manipulatedWindow === manipulated)
            state.cancelPointer()
            state.removeWindow(tiled, remember: true)
            let restorationReport = state.diagnosticReport
            #expect(restorationReport.contains("Restoration snapshots: 1"))
            #expect(restorationReport.contains("W1 kind=tiled"))
            let returning = TestWindow.new(id: 1, workspace: workspace)
            #expect(state.restoreWindow(newlyDetectedWindow: returning))
        }

        @Test func diagnosticReadDoesNotCreateFallbackDisplay() {
            let state = DisplayLayoutState(monitors: [], pointer: TestPointerAdapter())
            #expect(state.workspaces.isEmpty)
            #expect(state.diagnosticReport.contains("Logical focus: display=none window=none"))
            #expect(state.workspaces.isEmpty)
        }

        @Test func exposesBrokenTreeMembershipWithoutRepairingIt() {
            let workspace = focus.workspace
            let window = TestWindow.new(id: 1, workspace: workspace)
            workspace.layout.remove(window.windowId)
            let report = workspace.state.diagnosticReport
            #expect(report.contains("Membership inconsistency: tiled W1 is absent from its display tree"))
            #expect(workspace.layout.windowIds.isEmpty)
            #expect(window.kind == .tiled)
        }

        @Test func showsCacheModelAndNativeListDifferencesWithoutInventingEmptyReads() {
            let observation = AppDiagnosticObservation(
                cachedWindowIds: [1, 2], listedWindowIds: [2, 4], focusedWindowId: 4, status: "success")
            let report = observation.report(modelWindowIds: [1, 3])
            #expect(report.contains("Cached but absent from model=[2]"))
            #expect(report.contains("Model but absent from cache=[3]"))
            #expect(report.contains("Listed but absent from cache=[4]"))
            #expect(report.contains("Cached but absent from AXWindows=[1]"))
            let failed = AppDiagnosticObservation(
                cachedWindowIds: [1], listedWindowIds: nil, focusedWindowId: nil, status: "AXWindows error=-25204"
            )
            .report(modelWindowIds: [1])
            #expect(failed.contains("AXWindows error=-25204"))
            #expect(!failed.contains("Cached but absent from AXWindows"))
        }

        @Test func frozenReportIgnoresLiveModelEditsAndOldCallbacks() {
            let window = TestWindow.new(id: 1, workspace: focus.workspace)
            let source = RecordingDiagnosticsSource()
            let model = DiagnosticsModel()
            defer { model.cancelCapture() }
            model.capture(source: source)
            let firstCallback = source.receive!
            let firstReport = model.report
            window.bindAsFloatingWindow(to: focus.workspace)
            #expect(model.report == firstReport)
            model.capture(source: source)
            firstCallback(
                42, .init(cachedWindowIds: [99], listedWindowIds: [99], focusedWindowId: 99, status: "old capture"))
            #expect(!model.report.contains("old capture"))
            #expect(model.report.contains("kind=floating"))
            source.receive?(
                42, .init(cachedWindowIds: [], listedWindowIds: [], focusedWindowId: nil, status: "new capture"))
            #expect(model.report.contains("new capture"))
            #expect(!model.isCapturing)
            #expect(source.jobs.first?.isCancelled == true)
        }

        @Test func notificationFailuresDoNotHideSuccessfulNativeWindowReads() {
            let observation = AppDiagnosticObservation(
                cachedWindowIds: [5930], listedWindowIds: [5930], focusedWindowId: 5930, status: "AXWindows error=0",
                subscriptionFailures: ["AXWindowCreated: error=-25207", "W5930 AXMoved: error=-25204"])
            let report = observation.report(modelWindowIds: [5930])
            #expect(report.contains("Notification setup failures"))
            #expect(report.contains("AXWindowCreated: error=-25207"))
            #expect(report.contains("W5930 AXMoved: error=-25204"))
            #expect(report.contains("Fresh AXWindows=[5930]"))
            #expect(report.contains("AX cache=[5930]; model=[5930]"))
        }

        @Test func deadlineKeepsPartialEvidenceAndRejectsLateResults() async throws {
            let source = RecordingDiagnosticsSource(pids: [42, 43])
            let model = DiagnosticsModel()
            defer { model.cancelCapture() }
            model.capture(source: source, timeout: .milliseconds(1))
            source.receive?(
                42, .init(cachedWindowIds: [1], listedWindowIds: [1], focusedWindowId: 1, status: "partial result"))
            try await Task.sleep(for: .milliseconds(30))
            #expect(!model.isCapturing)
            #expect(model.report.contains("partial result"))
            #expect(model.report.contains("pid=43\n  Unavailable"))
            #expect(source.jobs.allSatisfy { $0.isCancelled })
            let finishedReport = model.report
            source.receive?(
                43, .init(cachedWindowIds: [2], listedWindowIds: [2], focusedWindowId: 2, status: "late result"))
            #expect(model.report == finishedReport)
        }

        @Test func sessionHistoryTracksDeltasCancellationAndBoundedRetention() {
            let history = SessionDiagnostics()
            let first = history.begin("refresh test", windowIds: [1, 2])
            #expect(history.report.contains("refresh test: in progress"))
            history.finish(first, outcome: "cancelled", windowIds: [2, 3])
            #expect(history.report.contains("cancelled; 2 windows; added=[3] removed=[1]"))
            for index in 0..<55 {
                let session = history.begin("session \(index)", windowIds: [])
                history.finish(session, outcome: "completed", windowIds: [])
            }
            #expect(history.recent.count == 50)
            #expect(history.recent.first?.contains("session 5:") == true)
        }

        @Test func actualRefreshRecordsObservationLossAndCancellation() async {
            let lost = TestWindow.new(id: 1, workspace: focus.workspace)
            let desktop = TestDesktopSessionAdapter()
            desktop.onRefreshWindows = {
                lost.layoutState.removeWindow(lost, remember: true)
                throw CancellationError()
            }
            let execution = ActionExecution(desktop: desktop)
            await execution.refresh(.ax("test loss"), assumeCancellable: true)
            #expect(
                execution.diagnostics.report.contains(
                    "refresh ax(test loss): cancelled; 0 windows; added=[] removed=[1]"))
            #expect(DisplayLayoutState.shared.diagnosticReport.contains("Restoration snapshots: 1"))
        }

        @Test func cancelledActionRecordsItsNameAndOutcome() async {
            let desktop = TestDesktopSessionAdapter()
            desktop.failFocusRead = true
            let execution = ActionExecution(desktop: desktop)
            do {
                _ = try await execution.execute(.close)
                Issue.record("Expected cancellation")
            } catch is CancellationError {
                #expect(execution.diagnostics.report.contains("action=close: cancelled"))
            } catch { Issue.record("Unexpected error: \(error)") }
        }
    }
}

@MainActor private final class RecordingDiagnosticsSource: DiagnosticsSource {
    let pids: [Int32]
    var jobs: [RunLoopJob] = []
    var receive: (@MainActor @Sendable (Int32, AppDiagnosticObservation) -> Void)?

    init(pids: [Int32] = [42]) { self.pids = pids }

    func snapshot() -> DiagnosticSnapshot {
        DiagnosticSnapshot(report: DisplayLayoutState.shared.diagnosticReport, modelWindowIds: [:], appPids: pids)
    }

    func observeApps(_ receive: @escaping @MainActor @Sendable (Int32, AppDiagnosticObservation) -> Void)
        -> [RunLoopJob]
    {
        self.receive = receive
        let current = pids.map { _ in RunLoopJob(.cancellable) }
        jobs += current
        return current
    }
}
