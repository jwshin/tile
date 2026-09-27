import Foundation
import Observation

/// Owns effective preferences and the lifetime of their active shortcuts.
@MainActor @Observable
final class ConfigurationApplication {
    static var shared = ConfigurationApplication(defaults: defaultConfig, shortcuts: NativeShortcutRegistrar())

    private(set) var current: Config
    private(set) var isEnabled = true
    private let defaults: Config
    private let shortcuts: any ShortcutRegistrar

    init(defaults: Config, shortcuts: any ShortcutRegistrar) {
        self.defaults = defaults
        current = defaults
        self.shortcuts = shortcuts
    }

    @discardableResult
    func apply(_ text: String) -> ConfigurationResult {
        let parsed = parseConfig(text, defaults: defaults)
        guard parsed.allowReloadConfig else {
            return ConfigurationResult(diagnostics: parsed.errors.map(\.description).joined(separator: "\n"))
        }
        current = parsed.config
        updateShortcuts()
        return ConfigurationResult(diagnostics: nil)
    }

    @discardableResult
    func reload(from url: URL? = nil) -> ConfigurationResult {
        let url = url ?? findCustomConfigUrl().urlOrNil ?? defaultConfigUrl
        do {
            let result = apply(try String(contentsOf: url, encoding: .utf8))
            return ConfigurationResult(diagnostics: result.diagnostics.map { "Failed to load \(url.path):\n\($0)" })
        } catch {
            return ConfigurationResult(diagnostics: "Can't read \(url.path): \(error.localizedDescription)")
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        updateShortcuts()
    }

    func stop() { shortcuts.replace(with: [:]) }

    private func updateShortcuts() {
        shortcuts.replace(with: isEnabled ? current.bindings : [:])
    }
}

struct ConfigurationResult {
    let diagnostics: String?
    var isOk: Bool { diagnostics == nil }
}
