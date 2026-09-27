import AppKit
import Darwin
import Foundation

@TaskLocal
public var refreshSessionEvent: RefreshSessionEvent? = nil

@TaskLocal
private var recursionDetectorDuringTermination = false

public func bugPrompt(
    _ __message: String = "",
    isDie: Bool = false,
    file: StaticString = #fileID,
    line: Int = #line,
    column: Int = #column,
    function: String = #function,
) -> String {
    let _message = __message.contains("\n") ? "\n" + __message.prefixLines(with: "    ") : __message
    let thread = Thread.current
    return """
        tile diagnostic
        Include the steps that triggered this error when investigating it.

        Message: \(_message)
        Version: \(appVersion)
        refreshSessionEvent: \(refreshSessionEvent.prettyDescription)
        Date: \(Date.now)
        Thread name: \(thread.name.prettyDescription)
        Is main thread: \(thread.isMainThread)
        axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken.prettyDescription)
        macOS version: \(ProcessInfo().operatingSystemVersionString)
        Coordinate: \(file):\(line):\(column) \(function)
        recursionDetectorDuringTermination: \(recursionDetectorDuringTermination)
        die: \(isDie)
        Monitor count: \(NSScreen.screens.count)
        Displays have separate spaces: \(NSScreen.screensHaveSeparateSpaces)

        Stacktrace:
        \(getStringStacktrace())
        """
}

public func dieT<T>(
    _ __message: String = "",
    file: StaticString = #fileID,
    line: Int = #line,
    column: Int = #column,
    function: String = #function,
) -> T {
    let message = bugPrompt(__message, isDie: true, file: file, line: line, column: column, function: function)
    if !isUnitTest {
        showMessageInGui(
            filenameIfConsoleApp: recursionDetectorDuringTermination
                ? "tile-runtime-error-recursion.txt"
                : "tile-runtime-error.txt",
            title: "tile runtime error",
            message: message,
        )
    }
    if let terminationHandler, !recursionDetectorDuringTermination {
        MainActor.runSync {
            $recursionDetectorDuringTermination.withValue(true) {
                terminationHandler.beforeTermination()
            }
        }
    }
    fatalError("\n" + message)
}

extension MainActor {
    static func runSync(block: @escaping @MainActor () -> Void) {
        switch Thread.isMainThread {
        case true: MainActor.assumeIsolated(block)
        case false: DispatchQueue.main.asyncAndWait { block() }
        }
    }
}

public enum RefreshSessionEvent: Sendable, CustomStringConvertible {
    case globalObserver(String)
    case globalObserverLeftMouseUp
    case menuBarButton
    case hotkeyBinding
    case startup
    case resetManipulatedWithMouse
    case ax(String)

    public var description: String {
        switch self {
        case .ax(let str): "ax(\(str))"
        case .globalObserver(let str): "globalObserver(\(str))"
        case .globalObserverLeftMouseUp: "globalObserverLeftMouseUp"
        case .hotkeyBinding: "hotkeyBinding"
        case .menuBarButton: "menuBarButton"
        case .resetManipulatedWithMouse: "resetManipulatedWithMouse"
        case .startup: "startup"
        }
    }
}

public func getStringStacktrace() -> String { Thread.callStackSymbols.joined(separator: "\n") }

@inlinable public func die(
    _ message: String = "",
    file: StaticString = #fileID,
    line: Int = #line,
    column: Int = #column,
    function: String = #function,
) -> Never {
    dieT(message, file: file, line: line, column: column, function: function)
}

public func check(
    _ condition: Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #fileID,
    line: Int = #line,
    column: Int = #column,
    function: String = #function,
) {
    if !condition {
        die(message(), file: file, line: line, column: column, function: function)
    }
}

public var isUnitTest: Bool {
    CommandLine.arguments.contains { $0.contains(".xctest") }
}

extension String {
    public func removePrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}

extension URL {
    public func open(with url: URL) {
        NSWorkspace.shared.open([self], withApplicationAt: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

public func eprint(_ msg: String) {
    unsafe fputs(msg + "\n", stderr)
}

public func exit(_ exitCode: Int32, out: String? = nil, err: String? = nil) -> Never {
    exitT(exitCode, out: out, err: err)
}

public func exitT<T>(_ exitCode: Int32, out: String? = nil, err: String? = nil) -> T {
    if let out { print(out) }
    if let err { eprint(err) }
    exit(exitCode)
}

/// 'id' stands for 'identity'. It's a common name in functional programming
public func id<T>(_ t: T) -> T { t }
