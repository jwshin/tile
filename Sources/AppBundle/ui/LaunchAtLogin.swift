import Common
import Foundation
import Observation
import ServiceManagement

@MainActor protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSettings()
}

@MainActor struct NativeLoginItemService: LoginItemService {
    var status: SMAppService.Status {
        // An unbundled debug executable must never become a login item.
        guard Bundle.main.bundleURL.pathExtension == "app", Bundle.main.bundleIdentifier == stableAppId else {
            return .notFound
        }
        return SMAppService.mainApp.status
    }

    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// Reflects macOS registration without storing a second preference or registering during startup.
@MainActor @Observable final class LaunchAtLogin {
    private let service: any LoginItemService
    private(set) var status: SMAppService.Status
    var isEnabled: Bool { status == .enabled }

    init(service: any LoginItemService) {
        self.service = service
        status = service.status
    }

    func refresh() { status = service.status }
    func openSettings() { service.openSettings() }

    /// Returns a diagnostic on failure; the displayed state always comes from macOS.
    func setEnabled(_ enabled: Bool) -> String? {
        refresh()
        guard status != .notFound else { return "Open the installed tile.app to configure Launch at login." }
        var failure: (any Error)?
        do {
            if enabled {
                if status == .notRegistered { try service.register() }
            } else if status == .enabled || status == .requiresApproval {
                try service.unregister()
            }
        } catch {
            failure = error
        }
        refresh()
        if enabled && status == .requiresApproval {
            service.openSettings()
            return nil
        }
        return failure.map { "Could not change Launch at login:\n\($0.localizedDescription)" }
    }
}
