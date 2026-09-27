public final class Port {
    public enum Direction {
        case input
        case output
    }

    public let direction: Direction
    public private(set) var isOpen = true
    private let inputChars: [Character]
    private var inputPos = 0
    private var outputBuffer = ""
    private let sink: ((String) -> Void)?

    private init(direction: Direction, inputChars: [Character], sink: ((String) -> Void)?) {
        self.direction = direction
        self.inputChars = inputChars
        self.sink = sink
    }

    public static func inputString(_ text: String) -> Port {
        Port(direction: .input, inputChars: Array(text), sink: nil)
    }

    public static func outputString() -> Port {
        Port(direction: .output, inputChars: [], sink: nil)
    }

    public static func sinkOutput(_ sink: @escaping (String) -> Void) -> Port {
        Port(direction: .output, inputChars: [], sink: sink)
    }

    public var isInput: Bool { direction == .input }

    public func close() {
        isOpen = false
    }

    private func ensureReadable(_ who: String) throws {
        guard direction == .input else { throw schemeError("\(who): not an input port") }
        guard isOpen else { throw schemeError("\(who): port is closed") }
    }

    private func ensureWritable(_ who: String) throws {
        guard direction == .output else { throw schemeError("\(who): not an output port") }
        guard isOpen else { throw schemeError("\(who): port is closed") }
    }

    public func peekChar() throws -> Character? {
        try ensureReadable("peek-char")
        return inputPos < inputChars.count ? inputChars[inputPos] : nil
    }

    public func readChar() throws -> Character? {
        try ensureReadable("read-char")
        guard inputPos < inputChars.count else { return nil }
        inputPos += 1
        return inputChars[inputPos - 1]
    }

    public func charReady() throws -> Bool {
        try ensureReadable("char-ready?")
        return true
    }

    public func readLine() throws -> String? {
        try ensureReadable("read-line")
        guard inputPos < inputChars.count else { return nil }
        var line = ""
        while inputPos < inputChars.count {
            let c = inputChars[inputPos]
            inputPos += 1
            if c == "\n" { break }
            line.append(c)
        }
        return line
    }

    public func readString(_ limit: Int) throws -> String? {
        try ensureReadable("read-string")
        guard inputPos < inputChars.count else { return nil }
        let end = min(inputChars.count, inputPos + max(limit, 0))
        let text = String(inputChars[inputPos..<end])
        inputPos = end
        return text
    }

    public func readDatum() throws -> Value {
        try ensureReadable("read")
        let reader = Reader(String(inputChars[inputPos...]))
        guard let datum = try reader.readOne() else {
            inputPos = inputChars.count
            return .eof
        }
        inputPos += reader.position
        return datum
    }

    public func write(_ text: String, _ who: String = "write") throws {
        try ensureWritable(who)
        if let sink {
            sink(text)
        } else {
            outputBuffer += text
        }
    }

    public func outputText() throws -> String {
        guard direction == .output, sink == nil else {
            throw schemeError("get-output-string: not a string output port")
        }
        return outputBuffer
    }
}
