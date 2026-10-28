import AppKit
import Common

/// The native and test adapters observe windows; tree/layout algorithms stay shared.
@MainActor protocol DesktopSessionAdapter {
    func focusedWindow() async throws -> Window?
    func refreshWindows() async throws
    func validatePopups() async throws
    func updateStatus()
}

enum ActionInput { case shortcut, menu }

@MainActor final class ActionExecution {
    static var shared = ActionExecution(desktop: NativeDesktopSessionAdapter())
    private let desktop: any DesktopSessionAdapter
    private var activeRefreshTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private let now: @MainActor () -> TimeInterval
    private let automaticallyPollRecovery: Bool
    let diagnostics = SessionDiagnostics()

    init(
        desktop: any DesktopSessionAdapter,
        now: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        automaticallyPollRecovery: Bool = true
    ) {
        self.desktop = desktop
        self.now = now
        self.automaticallyPollRecovery = automaticallyPollRecovery
    }

    func displayWillSleep(_ reason: DisplayRecovery.Reason) {
        cancelRefresh()
        recoveryTask?.cancel()
        recoveryTask = nil
        DisplayLayoutState.shared.beginDisplaySleep(reason)
        MacApp.cancelPendingFocus()
    }

    func displayDidWake(_ reason: DisplayRecovery.Reason) {
        DisplayLayoutState.shared.beginDisplayWake(reason, at: now())
        scheduleRefresh(.globalObserver("DisplayWakeRecovery"))
    }

    private func displaysReady() -> Bool {
        let state = DisplayLayoutState.shared
        state.advanceDisplayRecovery(monitorInfos, at: now())
        guard state.isRecoveringDisplays else { return true }
        if automaticallyPollRecovery, recoveryTask == nil, state.displayRecovery.shouldPoll(at: now()) {
            recoveryTask = Task { @MainActor [weak self] in
                guard let self else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                    guard !Task.isCancelled else { return }
                    let state = DisplayLayoutState.shared
                    state.advanceDisplayRecovery(monitorInfos, at: now())
                    if !state.isRecoveringDisplays {
                        recoveryTask = nil
                        scheduleRefresh(.globalObserver("DisplayWakeRecovery"))
                        return
                    }
                    if !state.displayRecovery.shouldPoll(at: now()) {
                        recoveryTask = nil
                        return
                    }
                }
            }
        }
        return false
    }

    @discardableResult
    func execute(_ action: Action, from input: ActionInput = .shortcut) async throws -> CmdResult {
        let allowedWhileDisabled = input == .menu && (action == .toggleTiling || action == .reloadConfig)
        guard displaysReady() else {
            // Configuration controls remain available without entering a native layout session.
            if allowedWhileDisabled {
                let io = CmdIo()
                let result = await action.command.run(io)
                desktop.updateStatus()
                return CmdResult(stdout: io.stdout, stderr: io.stderr, exitCode: result)
            }
            return CmdResult(
                stdout: [], stderr: ["Displays are recovering from sleep; try again shortly."], exitCode: .fail)
        }
        guard ConfigurationApplication.shared.isEnabled || allowedWhileDisabled else {
            return CmdResult(stdout: [], stderr: [], exitCode: .fail)
        }
        DisplayLayoutState.shared.cancelPointer()
        return try await runSession(
            input == .menu ? .menuBarButton : .hotkeyBinding, .forceRun, action: action.rawValue
        ) {
            let command = action.command
            let io = CmdIo()
            let result =
                command.invalidatesRestoration
                ? await DisplayLayoutState.shared.changeLayout { await command.run(io) }
                : await command.run(io)
            return CmdResult(stdout: io.stdout, stderr: io.stderr, exitCode: result)
        }
    }

    func cancelRefresh() {
        activeRefreshTask?.cancel()
        activeRefreshTask = nil
    }

    func scheduleRefresh(_ event: RefreshSessionEvent, optimisticallyPreLayoutWorkspaces: Bool = false) {
        cancelRefresh()
        guard displaysReady() else { return }
        activeRefreshTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            await refresh(
                event, assumeCancellable: true,
                optimisticallyPreLayoutWorkspaces: optimisticallyPreLayoutWorkspaces)
        }
    }

    func refresh(
        _ event: RefreshSessionEvent, assumeCancellable: Bool,
        layoutWorkspaces shouldLayout: Bool = true, optimisticallyPreLayoutWorkspaces: Bool = false
    ) async {
        let interval = signposter.beginInterval(#function, "event: \(event)")
        defer { signposter.endInterval(#function, interval) }
        let session = diagnostics.begin(
            "refresh \(event)", windowIds: DisplayLayoutState.shared.allWindows.map(\.windowId))
        var outcome = "disabled"
        defer {
            diagnostics.finish(
                session, outcome: outcome, windowIds: DisplayLayoutState.shared.allWindows.map(\.windowId))
        }
        guard ConfigurationApplication.shared.isEnabled else { return }
        guard displaysReady() else {
            outcome = "display recovery"
            return
        }
        let state = DisplayLayoutState.shared
        let generation = state.lifecycleGeneration
        outcome = "completed"
        do {
            try await $refreshSessionEvent.withValue(event) {
                // Reconcile departures before importing macOS's possibly automatic focus replacement.
                let spaceTransition: Bool
                if case .globalObserver(let name) = event {
                    spaceTransition = name == NSWorkspace.activeSpaceDidChangeNotification.rawValue
                } else {
                    spaceTransition = false
                }
                var preserveNativeFocus = spaceTransition
                // Clear even on cancellation: a later AX refresh must not replay this recovery.
                defer {
                    if preserveNativeFocus { DisplayLayoutState.shared.discardFocusRecovery() }
                }
                if preserveNativeFocus { DisplayLayoutState.shared.discardFocusRecovery() }
                let nativeFocus = try await desktop.focusedWindow()
                try state.checkLifecycle(generation)
                let nativeFullscreen = try await nativeFocus?.isMacosFullscreen(.cancellable)
                try state.checkLifecycle(generation)
                preserveNativeFocus = preserveNativeFocus || (nativeFocus != nil && nativeFullscreen != false)
                if preserveNativeFocus { DisplayLayoutState.shared.discardFocusRecovery() }
                if shouldLayout && optimisticallyPreLayoutWorkspaces {
                    try await layoutWorkspaces(preservingPointerInputFrom: nativeFocus)
                }
                refreshModel()
                try await desktop.refreshWindows()
                try state.checkLifecycle(generation)
                DisplayLayoutState.shared.reconcileMonitors(monitorInfos)
                if try await normalizeLayoutReason() {
                    // A native-focused window may only become focusable after its state returns.
                    let returnedFocus = try await desktop.focusedWindow()
                    try state.checkLifecycle(generation)
                    DisplayLayoutState.shared.importNativeFocus(returnedFocus)
                } else {
                    DisplayLayoutState.shared.importNativeFocus(nativeFocus)
                }
                desktop.updateStatus()
                try await desktop.validatePopups()
                try state.checkLifecycle(generation)
                if shouldLayout { try await layoutWorkspaces(preservingPointerInputFrom: nativeFocus) }
                try state.checkLifecycle(generation)
                if preserveNativeFocus {
                    DisplayLayoutState.shared.discardFocusRecovery()
                }
                DisplayLayoutState.shared.takeFocusRecovery()?.windowOrNil?.nativeFocus()
            }
        } catch is CancellationError {
            outcome = "cancelled"
            check(
                assumeCancellable || state.lifecycleGeneration != generation,
                "Non cancellable refresh session was canceled")
        } catch {
            outcome = "failed: \(error)"
            die("Illegal error: \(error)")
        }
    }

    func runSession<T>(
        _ event: RefreshSessionEvent, _: RunSessionGuard,
        action: String? = nil,
        body: @MainActor () async throws -> T
    ) async throws -> T {
        guard displaysReady() else { throw CancellationError() }
        let state = DisplayLayoutState.shared
        let generation = state.lifecycleGeneration
        let interval = signposter.beginInterval(#function, "event: \(event)")
        defer { signposter.endInterval(#function, interval) }
        let session = diagnostics.begin(
            "session \(event)\(action.map { " action=\($0)" } ?? "")",
            windowIds: DisplayLayoutState.shared.allWindows.map(\.windowId))
        var outcome = "interrupted"
        defer {
            diagnostics.finish(
                session, outcome: outcome, windowIds: DisplayLayoutState.shared.allWindows.map(\.windowId))
        }
        cancelRefresh()
        do {
            return try await $refreshSessionEvent.withValue(event) {
                let nativeFocus = try await desktop.focusedWindow()
                try state.checkLifecycle(generation)
                DisplayLayoutState.shared.importNativeFocus(nativeFocus)
                let focusBefore = focus.windowOrNil
                refreshModel()
                let result = try await body()
                try state.checkLifecycle(generation)
                refreshModel()
                let focusAfter = focus.windowOrNil
                desktop.updateStatus()
                try await layoutWorkspaces()
                try state.checkLifecycle(generation)
                let recovery = DisplayLayoutState.shared.takeFocusRecovery()
                if recovery != nil || focusBefore != focusAfter { focusAfter?.nativeFocus() }
                scheduleRefresh(event)
                outcome = "completed"
                return result
            }
        } catch {
            outcome = error is CancellationError ? "cancelled" : "failed: \(error)"
            throw error
        }
    }

    private func refreshModel() {
        DisplayLayoutState.shared.reconcileMonitors(monitorInfos)
    }

    private func layoutWorkspaces(preservingPointerInputFrom nativeFocus: Window? = nil) async throws {
        guard ConfigurationApplication.shared.isEnabled, !monitorInfos.isEmpty,
            !DisplayLayoutState.shared.isRecoveringDisplays
        else { return }
        for workspace in DisplayLayoutState.shared.workspaces {
            // A passive refresh can run before the first move/resize notification. The native
            // focused window already belongs to the held pointer during that interval.
            let pendingWindow = workspace.state.isPointerDown && !workspace.state.isHandlingPointer ? nativeFocus : nil
            try await workspace.layoutWorkspace(preservingPointerWindow: pendingWindow)
        }
    }
}

struct RunSessionGuard: Sendable {
    @MainActor static var isEnabled: RunSessionGuard? {
        ConfigurationApplication.shared.isEnabled && !DisplayLayoutState.shared.isRecoveringDisplays ? forceRun : nil
    }
    static let forceRun = RunSessionGuard()
    private init() {}
}
