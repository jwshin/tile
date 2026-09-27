public let EXIT_CODE_ZERO: Int32 = 0
public let EXIT_CODE_TWO: Int32 = 2

public enum BinaryExitCode: Int32, Sendable {
    case succ = 0
    case fail = 2
    public static func from(bool: Bool) -> Self { bool ? .succ : .fail }

    public static func fail(_ _: IoSideEffect) -> Self { .fail }
}

public enum IoSideEffect {
    case instance
}
