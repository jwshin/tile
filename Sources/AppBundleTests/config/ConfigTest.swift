import AppKit
import Common
import Testing

@testable import AppBundle

extension CoreTests {
    @MainActor struct ConfigTest {
        init() { setUpWorkspacesForTests() }

        @Test func bundledConfigHasWorkingDefaults() throws {
            let result = parseConfig(try String(contentsOf: defaultConfigUrl, encoding: .utf8))
            #expect(result.errors.isEmpty)
            #expect(result.config.gap == 8)
            #expect(result.config.bindings.count == 23)
            #expect(result.config.bindings["alt-h"]?.action == .focusLeft)
            #expect(result.config.bindings["alt-shift-tab"]?.action == .moveToNextMonitor)
        }

        @Test func omittedBindingsKeepDefaultShortcuts() {
            for contents in ["", "gap = 12", "new-window-placement = 'inner'"] {
                let result = parseConfig(contents)
                #expect(result.errors.isEmpty)
                #expect(result.config.bindings == defaultConfig.bindings)
                #expect(result.config.bindings["alt-h"]?.action == .focusLeft)
                #expect(result.config.bindings["alt-shift-r"]?.action == .reloadConfig)
            }
            #expect(parseConfig("gap = 12").config.gap == 12)
            #expect(parseConfig("new-window-placement = 'inner'").config.newWindowPlacement == .inner)
        }

        @Test func explicitBindingsReplaceDefaultShortcuts() {
            let custom = parseConfig("[bindings]\nalt-h = 'close'")
            #expect(custom.errors.isEmpty)
            #expect(custom.config.bindings.count == 1)
            #expect(custom.config.bindings["alt-h"]?.action == .close)
            let empty = parseConfig("[bindings]")
            #expect(empty.errors.isEmpty)
            #expect(empty.config.bindings.isEmpty)
        }

        @Test func personalPreferencesAndFixedQwertyKeys() {
            let result = parseConfig(
                """
                gap = 12
                new-window-placement = 'inner'
                [bindings]
                ctrl-alt-h = 'focus-left'
                """)
            #expect(result.errors.isEmpty)
            #expect(result.config.gap == 12)
            #expect(result.config.newWindowPlacement == .inner)
            let binding = result.config.bindings["alt-ctrl-h"]
            #expect(binding?.keyCode == .h)
            #expect(binding?.action == .focusLeft)
        }

        @Test func everyNamedActionCanBeBound() {
            for action in Action.allCases {
                let result = parseConfig("[bindings]\nalt-h = '\(action.rawValue)'")
                #expect(result.errors.isEmpty)
                #expect(result.config.bindings["alt-h"]?.action == action)
            }
        }

        @Test func retiredSettingsAreRejected() {
            for key in [
                "floating-apps", "gaps", "key-mapping", "mode", "on-window-detected", "after-startup-command",
                "persistent-workspaces", "auto-reload-config", "start-at-login",
                "default-root-container-orientation", "enable-normalization-flatten-containers",
                "enable-normalization-opposite-orientation-for-nested-containers",
            ] {
                let result = parseConfig("\(key) = []")
                #expect(!result.allowReloadConfig)
                #expect(result.errors.first?.message == "Unknown top-level key")
            }
        }

        @Test func commandsFlagsAndSequencesAreRejected() {
            for value in [
                "'focus left'", "'focus-left --window-id 1'", "'focus dfs-next'",
                "'focus-monitor main'", "'focus-left && close'", "['focus-left', 'close']", "''", "true",
            ] {
                #expect(!parseConfig("[bindings]\nalt-h = \(value)").allowReloadConfig)
            }
        }

        @Test func validatesGapTypesAndShortcutCollisions() {
            for value in ["-1", "true", "'8'", "[8]", "1.5"] {
                #expect(!parseConfig("gap = \(value)").allowReloadConfig)
            }
            #expect(parseConfig("gap = 0").config.gap == 0)
            #expect(parseConfig("").config.gap == 8)
            #expect(!parseConfig("new-window-placement = 'left'").allowReloadConfig)
            #expect(!parseConfig("root-orientation = 'diagonal'").allowReloadConfig)
            #expect(parseConfig("root-orientation = 'vertical'").config.rootOrientation == .vertical)
            #expect(!parseConfig("[bindings]\nalt-unicorn = 'close'").allowReloadConfig)
            #expect(!parseConfig("[bindings]\nalt-ctrl-h = 'close'\nctrl-alt-h = 'grow'").allowReloadConfig)
            #expect(!parseConfig("[bindings").allowReloadConfig)
        }
    }
}
