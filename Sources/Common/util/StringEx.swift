import Foundation

extension String: @retroactive LocalizedError {  // Make it possible to use String in Result. todo migrate to self written Result monad
    public var errorDescription: String? { self }
}

extension String {
    public func prefixLines(with: String) -> String {
        split(separator: "\n", omittingEmptySubsequences: false).map { with + $0 }.joined(separator: "\n")
    }

    public var singleQuoted: String { "'" + self + "'" }
}
