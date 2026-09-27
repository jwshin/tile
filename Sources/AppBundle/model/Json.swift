import AppKit
import Common

enum Json: Equatable {  // todo rename to Dto? (data transfer object)
    // vector
    case dict(JsonDict)
    case array(JsonArray)

    // scalar
    case null
    case string(String)
    case int(Int64)
    case bool(Bool)

    typealias JsonDict = [String: Json]
    typealias JsonArray = [Json]

    static func newOrDieRecursive(_ value: Any?) -> Json {
        switch value {
        case let value as [String: Any?]: .dict(value.mapValues(newOrDieRecursive))
        case let value as [Any?]: .array(value.map(newOrDieRecursive))
        default:
            newScalarOrNil(value)
                ?? dieT("Can't parse \(String(describing: value)) (\(Swift.type(of: value))) to JSON")
        }
    }

    static func newScalarOrNil(_ value: Any?) -> Json? {
        switch value {
        case let value as Int64: .int(value)
        case let value as Int: .int(Int64(value))
        case let value as UInt32: .int(Int64(value))
        case let value as UInt: .int(Int64(value))
        case let value as Bool: .bool(value)
        case let value as String: .string(value)
        case nil, is NSNull: .null
        default: nil
        }
    }

    static func int(_ int: UInt32) -> Json { .int(Int64(exactly: int).orDie()) }

    var rawValue: Any? {
        switch self {
        case .null: nil

        case .array(let x): x
        case .dict(let x): x

        case .bool(let x): x
        case .int(let x): x
        case .string(let x): x
        }
    }

    var asDictOrDie: [String: Json] { asDictOrNil.orDie("\(self) is not a dict") }

    var asInt64OrNil: Int64? {
        if case .int(let value) = self { value } else { nil }
    }

    var asDictOrNil: JsonDict? {
        if case .dict(let value) = self { value } else { nil }
    }
}
