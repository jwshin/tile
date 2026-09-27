extension Result {
    public init(catching body: () async throws(Failure) -> Success) async {
        do {
            self = .success(try await body())
        } catch {
            self = .failure(error)
        }
    }

    public func getOrNil(appendErrorTo errors: inout [Failure]) -> Success? {
        switch self {
        case .success(let success):
            return success
        case .failure(let error):
            errors.append(error)
            return nil
        }
    }
}

extension Result {
    @discardableResult
    public func getOrDie(
        _ msgPrefix: String = "",
        file: StaticString = #fileID,
        line: Int = #line,
        column: Int = #column,
        function: String = #function,
    ) -> Success {
        switch self {
        case .success(let suc):
            return suc
        case .failure(let e):
            die(msgPrefix + e.localizedDescription, file: file, line: line, column: column, function: function)
        }
    }
}
