import AppKit
import Testing

@Suite(.serialized)
struct CoreTests {}

func recordFailure(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
    Issue.record(
        Comment(rawValue: message),
        sourceLocation: SourceLocation(
            fileID: String(describing: file), filePath: String(describing: file), line: Int(line), column: 1))
}

func expectEqual<T: Equatable>(
    _ actual: T, _ expected: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line
) {
    if actual != expected { recordFailure("\(message) Expected \(expected), got \(actual)", file: file, line: line) }
}
func expectNotEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual == expected { recordFailure("Unexpected equality: \(actual)", file: file, line: line) }
}
func expectTrue(_ actual: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    expectEqual(actual, true, message, file: file, line: line)
}
func expectFalse(_ actual: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    expectEqual(actual, false, message, file: file, line: line)
}
