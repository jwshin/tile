import AppKit
import Common
import Foundation
import HotKey

@MainActor private var hotkeys: [String: HotKey] = [:]

@MainActor func resetHotKeys() {
    // Explicitly unregister all hotkeys. We cannot always rely on destruction of the HotKey object to trigger
    // unregistration because we might be running inside a hotkey handler that is keeping its HotKey object alive.
    for (_, key) in hotkeys {
        key.isEnabled = false
    }
    hotkeys = [:]
}

extension HotKey {
    var isEnabled: Bool {
        get { !isPaused }
        set {
            if isEnabled != newValue {
                isPaused = !newValue
            }
        }
    }
}

@MainActor func syncHotkeys() {
    resetHotKeys()
    guard TrayMenuModel.shared.isEnabled else { return }
    for binding in config.bindings.values {
        hotkeys[binding.descriptionWithKeyCode] = HotKey(
            key: binding.keyCode, modifiers: binding.modifiers,
            keyDownHandler: {
                _ = Task { @MainActor in
                    guard let guardToken = RunSessionGuard.isEnabled else { return }
                    try await runLightSession(.hotkeyBinding, guardToken) {
                        let result = await binding.action.run()
                        if result.exitCode.rawValue != 0 && !result.diagnostics.isEmpty {
                            MessageModel.shared.message = Message(
                                body: result.diagnostics)
                        }
                    }
                }
            })
    }
}

struct HotkeyBinding: Equatable, Sendable {
    let modifiers: NSEvent.ModifierFlags
    let keyCode: Key
    let action: Action
    let descriptionWithKeyCode: String

    init(
        _ modifiers: NSEvent.ModifierFlags, _ keyCode: Key, _ action: Action
    ) {
        self.modifiers = modifiers
        self.keyCode = keyCode
        self.action = action
        self.descriptionWithKeyCode =
            modifiers.isEmpty
            ? keyCode.toString()
            : modifiers.toString() + "-" + keyCode.toString()
    }

}

func parseBindings(
    _ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ errors: inout [ConfigParseDiagnostic]
) -> [String: HotkeyBinding] {
    guard let table = raw.asDictOrNil else {
        errors.append(expectedActualTypeDiagnostic(expected: .table, actual: raw.tomlType, backtrace))
        return [:]
    }
    var result: [String: HotkeyBinding] = [:]
    for (shortcut, value) in table {
        let path = backtrace + .key(shortcut)
        guard let (modifiers, key) = parseBinding(shortcut, path).getOrNil(appendErrorTo: &errors) else { continue }
        guard let name = parseString(value, path).getOrNil(appendErrorTo: &errors) else { continue }
        guard let action = Action(rawValue: name) else {
            errors.append(
                .init(
                    path,
                    "Unknown action '\(name)'. Expected one named action; arguments and sequences are unsupported."))
            continue
        }
        let binding = HotkeyBinding(modifiers, key, action)
        if result.updateValue(binding, forKey: binding.descriptionWithKeyCode) != nil {
            errors.append(.init(path, "'\(binding.descriptionWithKeyCode)' Binding redeclaration"))
        }
    }
    return result
}

func parseBinding(_ raw: String, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<
    (NSEvent.ModifierFlags, Key)
> {
    let rawKeys = raw.split(separator: "-")
    let modifiers: ResOrConfigParseDiagnostic<NSEvent.ModifierFlags> = rawKeys.dropLast()
        .mapAllOrFailure {
            modifiersMap[String($0)].toResult(.init(backtrace, "Can't parse modifiers in '\(raw)' binding"))
        }
        .map { NSEvent.ModifierFlags($0) }
    let key: ResOrConfigParseDiagnostic<Key> = rawKeys.last.flatMap { keyNotationToKeyCode[String($0)] }
        .toResult(.init(backtrace, "Can't parse the key in '\(raw)' binding"))
    return modifiers.flatMap { modifiers -> ResOrConfigParseDiagnostic<(NSEvent.ModifierFlags, Key)> in
        key.flatMap { key -> ResOrConfigParseDiagnostic<(NSEvent.ModifierFlags, Key)> in
            .success((modifiers, key))
        }
    }
}
