nonisolated(unsafe) public var _terminationHandler: TerminationHandler? = nil
public var terminationHandler: TerminationHandler? { unsafe _terminationHandler }

public protocol TerminationHandler: Sendable {
    @MainActor
    func beforeTermination()
}
