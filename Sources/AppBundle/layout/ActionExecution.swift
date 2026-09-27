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
        MouseTiling.shared.cancel()
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
                DisplayLayoutState.shared.importNativeFocus(try await desktop.focusedWindow())
                if shouldLayout && optimisticallyPreLayoutWorkspaces { try await layoutWorkspaces() }
                refreshModel()
                try await desktop.refreshWindows()
                DisplayLayoutState.shared.reconcileMonitors(monitorInfos)
                desktop.updateStatus()
                try await normalizeLayoutReason()
                try await desktop.validatePopups()
                if shouldLayout { try await layoutWorkspaces() }
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
            if focusBefore != focusAfter { focusAfter?.nativeFocus() }
            scheduleRefresh(event)
            return result
        }
    }

    private func refreshModel() {
        DisplayLayoutState.shared.reconcileMonitors(monitorInfos)
    }

    private func layoutWorkspaces() async throws {
        guard ConfigurationApplication.shared.isEnabled else { return }
        for workspace in DisplayLayoutState.shared.workspaces { try await workspace.layoutWorkspace() }
    }
}

struct RunSessionGuard: Sendable {
    @MainActor static var isEnabled: RunSessionGuard? {
        ConfigurationApplication.shared.isEnabled ? forceRun : nil
    }
    static let forceRun = RunSessionGuard()
    private init() {}
}
