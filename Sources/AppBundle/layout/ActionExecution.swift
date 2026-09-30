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

    init(desktop: any DesktopSessionAdapter) { self.desktop = desktop }

    @discardableResult
    func execute(_ action: Action, from input: ActionInput = .shortcut) async throws -> CmdResult {
        let allowedWhileDisabled = input == .menu && (action == .toggleTiling || action == .reloadConfig)
        guard ConfigurationApplication.shared.isEnabled || allowedWhileDisabled else {
            return CmdResult(stdout: [], stderr: [], exitCode: .fail)
        }
        DisplayLayoutState.shared.cancelPointer()
        return try await runSession(input == .menu ? .menuBarButton : .hotkeyBinding, .forceRun) {
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
        guard ConfigurationApplication.shared.isEnabled else { return }
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
                let nativeFullscreen = try await nativeFocus?.isMacosFullscreen(.cancellable) ?? false
                preserveNativeFocus = preserveNativeFocus || nativeFullscreen
                if preserveNativeFocus { DisplayLayoutState.shared.discardFocusRecovery() }
                if shouldLayout && optimisticallyPreLayoutWorkspaces {
                    try await layoutWorkspaces(preservingPointerInputFrom: nativeFocus)
                }
                refreshModel()
                try await desktop.refreshWindows()
                DisplayLayoutState.shared.reconcileMonitors(monitorInfos)
                if try await normalizeLayoutReason() {
                    // A native-focused window may only become focusable after its state returns.
                    DisplayLayoutState.shared.importNativeFocus(try await desktop.focusedWindow())
                } else {
                    DisplayLayoutState.shared.importNativeFocus(nativeFocus)
                }
                desktop.updateStatus()
                try await desktop.validatePopups()
                if shouldLayout { try await layoutWorkspaces(preservingPointerInputFrom: nativeFocus) }
                if preserveNativeFocus {
                    DisplayLayoutState.shared.discardFocusRecovery()
                }
                DisplayLayoutState.shared.takeFocusRecovery()?.windowOrNil?.nativeFocus()
            }
        } catch is CancellationError {
            check(assumeCancellable, "Non cancellable refresh session was canceled")
        } catch { die("Illegal error: \(error)") }
    }

    func runSession<T>(
        _ event: RefreshSessionEvent, _: RunSessionGuard,
        body: @MainActor () async throws -> T
    ) async throws -> T {
        let interval = signposter.beginInterval(#function, "event: \(event)")
        defer { signposter.endInterval(#function, interval) }
        cancelRefresh()
        return try await $refreshSessionEvent.withValue(event) {
            DisplayLayoutState.shared.importNativeFocus(try await desktop.focusedWindow())
            let focusBefore = focus.windowOrNil
            refreshModel()
            let result = try await body()
            refreshModel()
            let focusAfter = focus.windowOrNil
            desktop.updateStatus()
            try await layoutWorkspaces()
            let recovery = DisplayLayoutState.shared.takeFocusRecovery()
            if recovery != nil || focusBefore != focusAfter { focusAfter?.nativeFocus() }
            scheduleRefresh(event)
            return result
        }
    }

    private func refreshModel() {
        DisplayLayoutState.shared.reconcileMonitors(monitorInfos)
    }

    private func layoutWorkspaces(preservingPointerInputFrom nativeFocus: Window? = nil) async throws {
        guard ConfigurationApplication.shared.isEnabled, !monitorInfos.isEmpty else { return }
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
        ConfigurationApplication.shared.isEnabled ? forceRun : nil
    }
    static let forceRun = RunSessionGuard()
    private init() {}
}
