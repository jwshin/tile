import Foundation
import Observation
import ServiceManagement
import Synchronization
import Testing

@testable import AppBundle

@MainActor private final class TestLoginItemService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var registrationStatus: SMAppService.Status = .enabled
    var failure: NSError?
    var statusOnFailure: SMAppService.Status?
    private(set) var registrations = 0
    private(set) var removals = 0
    private(set) var settingsOpens = 0

    func register() throws {
        registrations += 1
        try failIfRequested()
        status = registrationStatus
    }

    func unregister() throws {
        removals += 1
        try failIfRequested()
        status = .notRegistered
    }

    func openSettings() { settingsOpens += 1 }

    private func failIfRequested() throws {
        if let failure {
            if let statusOnFailure { status = statusOnFailure }
            throw failure
        }
    }
}

extension CoreTests {
    @MainActor struct LaunchAtLoginTest {
        @Test func startupAndRefreshOnlyReadRegistration() {
            let service = TestLoginItemService()
            let model = LaunchAtLogin(service: service)
            #expect(!model.isEnabled)
            service.status = .enabled
            model.refresh()
            #expect(model.isEnabled)
            service.status = .requiresApproval
            model.refresh()
            #expect(!model.isEnabled && model.status == .requiresApproval)
            #expect(service.registrations == 0 && service.removals == 0 && service.settingsOpens == 0)
        }

        @Test func toggleRegistersAndUnregistersWithoutDuplicateRequests() {
            let service = TestLoginItemService()
            let model = LaunchAtLogin(service: service)
            #expect(model.setEnabled(true) == nil)
            #expect(model.isEnabled && service.registrations == 1)
            #expect(model.setEnabled(true) == nil)
            #expect(service.registrations == 1)
            #expect(model.setEnabled(false) == nil)
            #expect(!model.isEnabled && service.removals == 1)
            #expect(model.setEnabled(false) == nil)
            #expect(service.removals == 1)
        }

        @Test func toggleRechecksChangesMadeOutsideTheApp() {
            let service = TestLoginItemService()
            let model = LaunchAtLogin(service: service)
            service.status = .enabled
            #expect(model.setEnabled(true) == nil)
            #expect(model.isEnabled && service.registrations == 0)
            service.status = .notRegistered
            #expect(model.setEnabled(false) == nil)
            #expect(!model.isEnabled && service.removals == 0)
        }

        @Test(arguments: [false, true])
        func pendingApprovalOpensSettingsOnlyAfterAnExplicitRequest(alreadyRegistered: Bool) {
            let service = TestLoginItemService()
            service.status = alreadyRegistered ? .requiresApproval : .notRegistered
            service.registrationStatus = .requiresApproval
            let model = LaunchAtLogin(service: service)
            #expect(service.settingsOpens == 0)
            #expect(model.setEnabled(true) == nil)
            #expect(!model.isEnabled && model.status == .requiresApproval)
            #expect(service.registrations == (alreadyRegistered ? 0 : 1))
            #expect(service.settingsOpens == 1)
            #expect(model.setEnabled(false) == nil)
            #expect(model.status == .notRegistered && service.removals == 1)
        }

        @Test func deniedRegistrationUsesApprovalStateEvenWhenTheAPIThrows() {
            let service = TestLoginItemService()
            service.failure = NSError(domain: SMAppServiceErrorDomain, code: 1)
            service.statusOnFailure = .requiresApproval
            let model = LaunchAtLogin(service: service)
            #expect(model.setEnabled(true) == nil)
            #expect(!model.isEnabled && service.settingsOpens == 1)
        }

        @Test(arguments: [false, true])
        func failedToggleReportsTheErrorAndKeepsNativeState(enabling: Bool) {
            let service = TestLoginItemService()
            service.status = enabling ? .notRegistered : .enabled
            service.failure = NSError(
                domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
            let model = LaunchAtLogin(service: service)
            #expect(model.setEnabled(enabling)?.contains("Permission denied") == true)
            #expect(model.isEnabled == !enabling)
            #expect(service.settingsOpens == 0)
        }

        @Test func missingBundleCannotBeRegistered() {
            let service = TestLoginItemService()
            service.status = .notFound
            let model = LaunchAtLogin(service: service)
            #expect(model.setEnabled(true)?.contains("installed tile.app") == true)
            #expect(!model.isEnabled && service.registrations == 0 && service.settingsOpens == 0)
        }

        @Test func externalStatusRefreshInvalidatesMenuObservation() {
            let service = TestLoginItemService()
            let model = LaunchAtLogin(service: service)
            let changed = Atomic<Bool>(false)
            withObservationTracking {
                _ = model.isEnabled
            } onChange: {
                changed.store(true, ordering: .relaxed)
            }
            service.status = .enabled
            model.refresh()
            let didChange = changed.load(ordering: .relaxed)
            #expect(didChange)
            #expect(model.isEnabled)
        }
    }
}
