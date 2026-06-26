public struct SchemeError: Error, CustomStringConvertible {
    public let message: String
    public let irritants: [Value]

    public init(_ message: String, irritants: [Value] = []) {
        self.message = message
        self.irritants = irritants
    }

    public var description: String {
        if irritants.isEmpty { return message }
        let parts = irritants.map { writeString($0) }.joined(separator: " ")
        return "\(message) \(parts)"
    }
}

func schemeError(_ message: String, _ irritants: [Value] = []) -> SchemeError {
    SchemeError(message, irritants: irritants)
}
