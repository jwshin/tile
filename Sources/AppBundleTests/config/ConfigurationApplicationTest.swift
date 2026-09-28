import Foundation
import Testing

@testable import AppBundle

@MainActor final class RecordingShortcutRegistrar: ShortcutRegistrar {
    private(set) var bindings: [String: HotkeyBinding] = [:]
    private(set) var replacements = 0
    func replace(with bindings: [String: HotkeyBinding]) {
        self.bindings = bindings
        replacements += 1
    }
}

extension CoreTests {
    @MainActor struct ConfigurationApplicationTest {
        private let shortcuts = RecordingShortcutRegistrar()

        @Test func reloadAppliesDefaultsAndReplacesShortcuts() throws {
            let application = ConfigurationApplication(defaults: defaultConfig, shortcuts: shortcuts)
            let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".toml")
            defer { try? FileManager.default.removeItem(at: url) }
            try "gap = 12".write(to: url, atomically: true, encoding: .utf8)
            #expect(application.reload(from: url).isOk)
            #expect(application.current.gap == 12)
            #expect(shortcuts.bindings == defaultConfig.bindings)
            #expect(shortcuts.replacements == 1)
            #expect(application.apply("[bindings]\nalt-h = 'close'").isOk)
            #expect(shortcuts.bindings.count == 1)
            #expect(shortcuts.bindings["alt-h"]?.action == .close)
            #expect(application.apply("[bindings]").isOk)
            #expect(shortcuts.bindings.isEmpty)
        }

        @Test func failedReloadRetainsPreferencesAndRegistrations() {
            let application = ConfigurationApplication(defaults: defaultConfig, shortcuts: shortcuts)
            application.apply("gap = 12")
            let previous = shortcuts.bindings
            #expect(!application.apply("gap = 20\n[bindings]\nalt-h = ['close']").isOk)
            #expect(application.current.gap == 12)
            #expect(shortcuts.bindings == previous)
            #expect(shortcuts.replacements == 1)
            let missing = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            #expect(!application.reload(from: missing).isOk)
            #expect(shortcuts.bindings == previous)
            #expect(shortcuts.replacements == 1)
        }

        @Test func invalidFloatingAppsPreserveCurrentConfigAndShortcuts() {
            let application = ConfigurationApplication(defaults: defaultConfig, shortcuts: shortcuts)
            #expect(application.apply("floating-apps = ['com.example.player']").isOk)
            let previous = shortcuts.bindings
            let invalid = application.apply("floating-apps = [123]\n[bindings]\nalt-h = 'close'")
            #expect(!invalid.isOk)
            #expect(application.current.floatingApps == ["com.example.player"])
            #expect(shortcuts.bindings == previous && shortcuts.replacements == 1)
            #expect(application.apply("floating-apps = []").isOk)
            #expect(application.current.floatingApps.isEmpty)
        }

        @Test func disabledReloadDefersRegistrationUntilEnabled() {
            let application = ConfigurationApplication(defaults: defaultConfig, shortcuts: shortcuts)
            application.apply("")
            application.setEnabled(false)
            #expect(shortcuts.bindings.isEmpty)
            application.apply("gap = 20\n[bindings]\nalt-h = 'close'")
            #expect(application.current.gap == 20)
            #expect(shortcuts.bindings.isEmpty)
            application.setEnabled(true)
            #expect(shortcuts.bindings.count == 1)
            #expect(shortcuts.bindings["alt-h"]?.action == .close)
            application.stop()
            #expect(shortcuts.bindings.isEmpty)
        }
    }
}
