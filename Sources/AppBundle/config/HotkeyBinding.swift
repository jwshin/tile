import AppKit
import Common
import Foundation
import HotKey

@MainActor protocol ShortcutRegistrar {
    func replace(with bindings: [String: HotkeyBinding])
}

@MainActor final class NativeShortcutRegistrar: ShortcutRegistrar {
    private var hotkeys: [HotKey] = []

    func replace(with bindings: [String: HotkeyBinding]) {
        // A running handler may retain its HotKey, so unregister explicitly.
        for key in hotkeys { key.isPaused = true }
        hotkeys = bindings.values.map { binding in
            HotKey(
                key: binding.keyCode, modifiers: binding.modifiers,
                keyDownHandler: {
                    _ = Task { @MainActor in
                        let result = try await ActionExecution.shared.execute(binding.action)
                        MessageModel.shared.present(result, for: binding.action)
                    }
                })
        }
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
