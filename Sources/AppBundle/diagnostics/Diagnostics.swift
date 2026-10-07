import AppKit
import Carbon
import Common
import Observation

struct AppDiagnosticObservation: Sendable {
    let cachedWindowIds: [UInt32]
    let listedWindowIds: [UInt32]?
    let focusedWindowId: UInt32?
    let status: String
    var subscriptionFailures: [String] = []

    func report(modelWindowIds: [UInt32]) -> String {
        let model = Set(modelWindowIds)
        let cached = Set(cachedWindowIds)
        var lines = [
            "  \(status); native focused window=\(focusedWindowId?.description ?? "unavailable")",
            "  AX cache=\(cachedWindowIds.sorted()); model=\(modelWindowIds.sorted())",
            "  Cached but absent from model=\(cached.subtracting(model).sorted())",
            "  Model but absent from cache=\(model.subtracting(cached).sorted())",
        ]
        if !subscriptionFailures.isEmpty {
            lines +=
                ["  Notification setup failures:"]
                + subscriptionFailures.map { "    \($0)" }
        }
        if let listedWindowIds {
            let listed = Set(listedWindowIds)
            lines += [
                "  Fresh AXWindows=\(listedWindowIds.sorted())",
                "  Listed but absent from cache=\(listed.subtracting(cached).sorted())",
                "  Cached but absent from AXWindows=\(cached.subtracting(listed).sorted())",
            ]
        }
        return lines.joined(separator: "\n")
    }
}

struct DiagnosticSnapshot {
    let report: String
    let modelWindowIds: [Int32: [UInt32]]
    let appPids: [Int32]
}

@MainActor protocol DiagnosticsSource {
    func snapshot() -> DiagnosticSnapshot
    func observeApps(_ receive: @escaping @MainActor @Sendable (Int32, AppDiagnosticObservation) -> Void)
        -> [RunLoopJob]
}

/// Freeze the model first, then add bounded native observations without reconciliation.
@MainActor @Observable public final class DiagnosticsModel {
    public static let shared = DiagnosticsModel()
    private var snapshot: DiagnosticSnapshot?
    private var observations: [Int32: AppDiagnosticObservation] = [:]
    private var unavailable: [Int32: String] = [:]
    private var pending: Set<Int32> = []
    private var generation: UInt64 = 0
    private var jobs: [RunLoopJob] = []
    private var deadline: Task<Void, Never>?
    var saveError: String?
    var isCapturing: Bool { !pending.isEmpty }

    var report: String {
        guard let snapshot else { return "Capture diagnostics to inspect Tile's state." }
        let apps = snapshot.appPids.map { pid in
            let result: String
            if let observation = observations[pid] {
                result = observation.report(modelWindowIds: snapshot.modelWindowIds[pid] ?? [])
            } else if let reason = unavailable[pid] {
                result = "  Unavailable: \(reason)"
            } else {
                result = "  Waiting for Accessibility thread…"
            }
            return "pid=\(pid)\n\(result)"
        }
        return snapshot.report + "\n\nACCESSIBILITY OBSERVATIONS (read after model capture)\n"
            + (apps.isEmpty ? "No registered Accessibility apps." : apps.joined(separator: "\n"))
    }

    func capture(source: any DiagnosticsSource = NativeDiagnosticsSource(), timeout: Duration = .seconds(3)) {
        cancelCapture()
        generation += 1
        let captureGeneration = generation
        snapshot = source.snapshot()
        observations = [:]
        unavailable = [:]
        pending = Set(snapshot?.appPids ?? [])
        guard !pending.isEmpty else { return }
        jobs = source.observeApps { [weak self] pid, observation in
            guard let self, self.generation == captureGeneration, self.pending.remove(pid) != nil else { return }
            self.observations[pid] = observation
            if self.pending.isEmpty { self.deadline?.cancel() }
        }
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard let self, self.generation == captureGeneration else { return }
            for pid in self.pending {
                self.unavailable[pid] = "Accessibility thread did not respond before the capture deadline."
            }
            self.pending = []
            for job in self.jobs { job.cancel() }
        }
    }

    func cancelCapture() {
        deadline?.cancel()
        deadline = nil
        for job in jobs { job.cancel() }
        jobs = []
        for pid in pending { unavailable[pid] = "Capture cancelled before the Accessibility thread replied." }
        pending = []
    }
}

@MainActor struct NativeDiagnosticsSource: DiagnosticsSource {
    func snapshot() -> DiagnosticSnapshot {
        let state = DisplayLayoutState.shared
        let apps = MacApp.allAppsMap.values.sorted { $0.pid < $1.pid }
        let windows = state.allWindows
        let frontmost = NSWorkspace.shared.frontmostApplication
        var lines = [
            "tile \(appVersion) state diagnostics — \(Date().ISO8601Format())",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString); pid=\(myPid) bundle=\(appId)",
            "Enabled=\(ConfigurationApplication.shared.isEnabled) readOnly=\(appOptions.isReadOnly) Accessibility=\(AXIsProcessTrusted()) secureInput=\(IsSecureEventInputEnabled())",
            "Frontmost app: pid=\(frontmost?.processIdentifier.description ?? "none") bundle=\(frontmost?.bundleIdentifier ?? "unknown")",
            "Preferences: gap=\(config.gap) placement=\(config.newWindowPlacement) orientation=\(config.rootOrientation) floatingApps=\(config.floatingApps) shortcuts=\(config.bindings.count)",
            "Read-only capture; no refresh, registration, layout, or focus action is performed.",
            "The model is frozen first; native reads occur later and may differ during transitions.",
            "Window titles and document contents are omitted. App names, bundle IDs, window IDs, and screen geometry are included.",
            "\n" + state.diagnosticReport,
            "\n" + ActionExecution.shared.diagnostics.report,
            "\nRUNNING APPS (regular apps and registered utility apps)",
        ]
        for app in NSWorkspace.shared.runningApplications.sorted(by: { $0.processIdentifier < $1.processIdentifier })
        where app.activationPolicy == .regular || MacApp.allAppsMap[app.processIdentifier] != nil {
            lines.append(
                "pid=\(app.processIdentifier) app=\(app.localizedName ?? "unknown") bundle=\(app.bundleIdentifier ?? "unknown") "
                    + "hidden=\(app.isHidden) terminated=\(app.isTerminated) AXRegistered=\(MacApp.allAppsMap[app.processIdentifier] != nil)"
            )
        }
        lines.append("\nON-SCREEN WINDOW SERVER LIST")
        lines.append(
            "Untracked entries are candidates for investigation, including unmanaged overlays. Off-screen, minimized, and other-Space windows may be absent normally."
        )
        if let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]
        {
            for entry in entries.sorted(by: {
                ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
                    < ($1[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
            }) {
                guard let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                    let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                    pid != myPid
                else { continue }
                let window = state.window(for: id)
                let tracked = window?.app.pid == pid
                let rect = (entry[kCGWindowBounds as String] as? NSDictionary).flatMap {
                    CGRect(dictionaryRepresentation: $0)
                }
                lines.append(
                    "W\(id) pid=\(pid) app=\(entry[kCGWindowOwnerName as String] as? String ?? "unknown") "
                        + "layer=\(entry[kCGWindowLayer as String] as? Int ?? -1) tracked=\(tracked) frame=\(String(describing: rect))"
                )
            }
        } else {
            lines.append("Window Server list unavailable.")
        }
        return DiagnosticSnapshot(
            report: lines.joined(separator: "\n"),
            modelWindowIds: Dictionary(grouping: windows, by: { $0.app.pid }).mapValues { $0.map(\.windowId) },
            appPids: apps.map(\.pid))
    }

    func observeApps(_ receive: @escaping @MainActor @Sendable (Int32, AppDiagnosticObservation) -> Void)
        -> [RunLoopJob]
    {
        MacApp.allAppsMap.values.map { app in
            app.captureDiagnostics { observation in receive(app.pid, observation) }
        }
    }
}
