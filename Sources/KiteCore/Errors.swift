public struct SchemeError: Error, CustomStringConvertible {
    public let message: String
    public let irritants: [Value]
    public let condition: Value?

    public init(_ message: String, irritants: [Value] = [], condition: Value? = nil) {
        self.message = message
        self.irritants = irritants
        self.condition = condition
    }

    public var description: String {
        if irritants.isEmpty { return message }
        let parts = irritants.map { writeString($0) }.joined(separator: " ")
        return "\(message) \(parts)"
    }

    var conditionValue: Value {
        condition ?? .errorObject(ErrorObject(message: message, irritants: irritants))
    }
}

func schemeError(_ message: String, _ irritants: [Value] = []) -> SchemeError {
    SchemeError(message, irritants: irritants)
}

func conditionError(_ condition: Value) -> SchemeError {
    if case .errorObject(let e) = condition {
        return SchemeError(e.message, irritants: e.irritants, condition: condition)
    }
    return SchemeError("uncaught exception: \(writeString(condition))", condition: condition)
}
