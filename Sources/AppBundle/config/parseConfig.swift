import AppKit
import Common
import TOMLDecoder

struct ConfigParseDiagnostic: Error, Equatable {
    let backtrace: ConfigBacktrace
    let message: String

    public init(_ backtrace: ConfigBacktrace, _ message: String) {
        check(!message.isEmpty)
        self.backtrace = backtrace
        self.message = message
    }

    var description: String {
        let backtraceDesc = backtrace.description
        return switch backtraceDesc.isEmpty {
        case true: "[ERROR] \(message)"
        case false: "[ERROR] \(backtraceDesc): \(message)"
        }
    }
}

typealias ResOrConfigParseDiagnostic<T> = Result<T, ConfigParseDiagnostic>

func tomlAnyToOrderedJsonRecursive(
    any: Any,
    _ backtrace: ConfigBacktrace,
    _ errors: inout [ConfigParseDiagnostic],
) -> OrderedJson? {
    switch any {
    case let dict as [String: Any]:
        var json = OrderedJson.JsonDict()
        for (key, tomlValue) in dict.sortedEntries {
            json[key] = tomlAnyToOrderedJsonRecursive(any: tomlValue, backtrace + .key(key), &errors)
        }
        return .dict(json)
    case let array as [Any]:
        var json = OrderedJson.JsonArray()
        for (index, tomlValue) in array.enumerated() {
            let element = tomlAnyToOrderedJsonRecursive(any: tomlValue, backtrace + .index(index), &errors)
            guard let element else { continue }
            json.append(element)
        }
        return .array(json)
    default:
        if let value = OrderedJson.newScalarOrNil(any) { return value }
        errors.append(.init(backtrace, "Unsupported TOML type: \(type(of: any))"))
        return nil
    }
}

struct ParseConfigResult {
    let config: Config
    let errors: [ConfigParseDiagnostic]

    var allowReloadConfig: Bool { errors.isEmpty }
}

@MainActor func parseConfig(_ rawToml: String, defaults: Config = defaultConfig) -> ParseConfigResult {
    var errors: [ConfigParseDiagnostic] = []

    let rawTable: OrderedJson.JsonDict
    do {
        let dict: [String: Any] = try .init(try TOMLTable(source: rawToml))
        var table = OrderedJson.JsonDict()
        for (key, value) in dict.sortedEntries {
            table[key] = tomlAnyToOrderedJsonRecursive(any: value, .rootKey(key), &errors)
        }
        rawTable = table
    } catch {
        errors.append(.init(.emptyRoot, error.description))
        rawTable = [:]
    }

    var parsed = defaults
    for (key, value) in rawTable {
        let path = ConfigBacktrace.rootKey(key)
        switch key {
        case "gap":
            if let gap = value.asIntOrNil, gap >= 0 {
                parsed.gap = gap
            } else {
                errors.append(.init(path, "Expected a non-negative integer"))
            }
        case "floating-apps":
            if let apps = parseArrayOfStrings(value, path).getOrNil(appendErrorTo: &errors) {
                parsed.floatingApps = apps
            }
        case "bindings":
            parsed.bindings = parseBindings(value, path, &errors)
        default: errors.append(.init(path, "Unknown top-level key"))
        }
    }
    return ParseConfigResult(config: parsed, errors: errors)
}

func parseString(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<String> {
    raw.asStringOrNil.toResult(expectedActualTypeDiagnostic(expected: .string, actual: raw.tomlType, backtrace))
}

func parseTomlArray(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<
    OrderedJson.JsonArray
> {
    raw.asArrayOrNil.toResult(expectedActualTypeDiagnostic(expected: .array, actual: raw.tomlType, backtrace))
}

private func parseArrayOfStrings(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<
    [String]
> {
    parseTomlArray(raw, backtrace)
        .flatMap { arr in
            arr.enumerated().mapAllOrFailure { (index, elem) in
                parseString(elem, backtrace + .index(index))
            }
        }
}

struct ConfigBacktrace: CustomStringConvertible, Equatable {
    private var path: [TomlBacktraceItem] = []
    private init(_ path: [TomlBacktraceItem]) {
        check(path.first?.isKey != false, "Tried to construct invalid TOML path: \(path)")
        self.path = path
    }

    static func rootKey(_ key: String) -> Self { .init([.key(key)]) }
    static let emptyRoot: Self = .init([])

    var description: String {
        var result = ""
        for (i, elem) in path.enumerated() {
            switch elem {
            case .key(let rootKey) where i == 0: result += rootKey
            case .key(let key): result += ".\(key)"
            case .index(let index): result += "[\(index)]"
            }
        }
        return result
    }

    static func + (lhs: consuming Self, rhs: TomlBacktraceItem) -> Self {
        lhs.path += [rhs]
        return lhs
    }
}

enum TomlBacktraceItem: Equatable {
    case key(String)
    case index(Int)

    var isKey: Bool {
        switch self {
        case .key: true
        case .index: false
        }
    }
}

func expectedActualTypeDiagnostic(expected: TomlType, actual: TomlType, _ backtrace: ConfigBacktrace)
    -> ConfigParseDiagnostic
{
    .init(backtrace, "Expected \(expected.rawValue), got \(actual.rawValue)")
}
