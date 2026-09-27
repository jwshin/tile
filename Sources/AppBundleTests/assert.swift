import AppKit
import Common
import Testing

@testable import AppBundle

func assertTrue(_ actual: Bool, file: StaticString = #filePath, line: UInt = #line) {
    assertEquals(actual, true, file: file, line: line)
}

func assertFalse(_ actual: Bool, file: StaticString = #filePath, line: UInt = #line) {
    assertEquals(actual, false, file: file, line: line)
}

// Because assertEquals default messages are unreadable!

func assertEquals<T>(
    _ actual: T, _ expected: T, additionalMsg: String? = nil, file: StaticString = #filePath, line: UInt = #line
) where T: Equatable {
    if actual != expected {
        failExpectedActual(expected, actual, additionalMsg: additionalMsg, file: file, line: line)
    }
}

func failExpectedActual(
    _ expected: Any?, _ actual: Any?, additionalMsg: String? = nil, file: StaticString = #filePath, line: UInt = #line
) {
    let additionalMsg = additionalMsg.map { "\n    Additional Message:\n        \($0)" } ?? ""
    recordFailure(
        """
        Assertion failed\(additionalMsg)
            Expected:
                \(expected.prettyDescription)
            Actual:
                \(actual.prettyDescription)
        """,
        file: file,
        line: line,
    )
}
