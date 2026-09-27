public final class Reader {
    private let chars: [Character]
    private var pos: Int

    public init(_ source: String) {
        self.chars = Array(source)
        self.pos = 0
    }

    public var position: Int { pos }

    public func readProgram() throws -> [Value] {
        var forms: [Value] = []
        while true {
            skipAtmosphere()
            if pos >= chars.count { break }
            forms.append(try readDatum())
        }
        return forms
    }

    public func readOne() throws -> Value? {
        skipAtmosphere()
        if pos >= chars.count { return nil }
        return try readDatum()
    }

    private func peek() -> Character? {
        pos < chars.count ? chars[pos] : nil
    }

    private func advance() -> Character {
        let c = chars[pos]
        pos += 1
        return c
    }

    private func isDelimiter(_ c: Character) -> Bool {
        c == "(" || c == ")" || c == "[" || c == "]" || c == "\"" || c == ";" || c == "'"
            || c == "`" || c == "," || c.isWhitespace
    }

    private func skipAtmosphere() {
        while pos < chars.count {
            let c = chars[pos]
            if c.isWhitespace {
                pos += 1
            } else if c == ";" {
                while pos < chars.count && chars[pos] != "\n" { pos += 1 }
            } else if c == "#" && pos + 1 < chars.count && chars[pos + 1] == "|" {
                skipBlockComment()
            } else if c == "#" && pos + 1 < chars.count && chars[pos + 1] == ";" {
                pos += 2
                skipAtmosphere()
                _ = try? readDatum()
            } else {
                break
            }
        }
    }

    private func skipBlockComment() {
        pos += 2
        var depth = 1
        while pos < chars.count && depth > 0 {
            if chars[pos] == "#" && pos + 1 < chars.count && chars[pos + 1] == "|" {
                depth += 1
                pos += 2
            } else if chars[pos] == "|" && pos + 1 < chars.count && chars[pos + 1] == "#" {
                depth -= 1
                pos += 2
            } else {
                pos += 1
            }
        }
    }

    private func readDatum() throws -> Value {
        skipAtmosphere()
        guard let c = peek() else {
            throw schemeError("unexpected end of input")
        }
        switch c {
        case "(", "[":
            return try readList(close: c == "(" ? ")" : "]")
        case ")", "]":
            throw schemeError("unexpected )")
        case "\"":
            return try readString()
        case "'":
            pos += 1
            return listOf("quote", try readDatum())
        case "`":
            pos += 1
            return listOf("quasiquote", try readDatum())
        case ",":
            pos += 1
            if peek() == "@" {
                pos += 1
                return listOf("unquote-splicing", try readDatum())
            }
            return listOf("unquote", try readDatum())
        case "#":
            return try readHash()
        default:
            return try readAtom()
        }
    }

    private func listOf(_ head: String, _ rest: Value) -> Value {
        cons(.symbol(head), cons(rest, .null))
    }

    private func readList(close: Character) throws -> Value {
        pos += 1
        var elements: [Value] = []
        var tail: Value = .null
        while true {
            skipAtmosphere()
            guard let c = peek() else {
                throw schemeError("unexpected end of input in list")
            }
            if c == close || c == ")" || c == "]" {
                pos += 1
                break
            }
            if c == "." && isDotSeparator() {
                pos += 1
                tail = try readDatum()
                skipAtmosphere()
                guard let cc = peek(), cc == close || cc == ")" || cc == "]" else {
                    throw schemeError("malformed dotted list")
                }
                pos += 1
                break
            }
            elements.append(try readDatum())
        }
        return arrayToList(elements, tail: tail)
    }

    private func isDotSeparator() -> Bool {
        guard chars[pos] == "." else { return false }
        let next = pos + 1
        if next >= chars.count { return true }
        return isDelimiter(chars[next])
    }

    private func readString() throws -> Value {
        pos += 1
        var out = ""
        while pos < chars.count {
            let c = advance()
            if c == "\"" {
                return .string(out)
            }
            if c == "\\" {
                guard pos < chars.count else { break }
                let e = advance()
                switch e {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "\\": out.append("\\")
                case "\"": out.append("\"")
                case "0": out.append("\u{0}")
                default: out.append(e)
                }
            } else {
                out.append(c)
            }
        }
        throw schemeError("unterminated string")
    }

    private func readHash() throws -> Value {
        pos += 1
        guard let c = peek() else { throw schemeError("bad # token") }
        if c == "t" {
            consumeWord()
            return .bool(true)
        }
        if c == "f" {
            consumeWord()
            return .bool(false)
        }
        if c == "\\" {
            pos += 1
            return try readChar()
        }
        if c == "(" {
            return .vector(VectorRef(try listToArray(try readList(close: ")"))))
        }
        if let radix = radixPrefixes[Character(c.lowercased())] {
            pos += 1
            var token = ""
            while pos < chars.count && !isDelimiter(chars[pos]) {
                token.append(advance())
            }
            guard let number = parseNumber(token, radix: radix) else {
                throw schemeError("bad number literal: #\(c)\(token)")
            }
            return number
        }
        throw schemeError("unsupported # syntax: #\(c)")
    }

    private func consumeWord() {
        while pos < chars.count && !isDelimiter(chars[pos]) {
            pos += 1
        }
    }

    private func readChar() throws -> Value {
        guard pos < chars.count else { throw schemeError("bad char literal") }
        var name = ""
        name.append(advance())
        while pos < chars.count && !isDelimiter(chars[pos]) {
            name.append(advance())
        }
        if name.count == 1 {
            return .char(name.first!)
        }
        switch name.lowercased() {
        case "space": return .char(" ")
        case "newline": return .char("\n")
        case "tab": return .char("\t")
        case "return": return .char("\r")
        case "null", "nul": return .char("\u{0}")
        case "delete", "rubout": return .char("\u{7f}")
        default:
            return .char(name.first!)
        }
    }

    private func readAtom() throws -> Value {
        var token = ""
        while pos < chars.count && !isDelimiter(chars[pos]) {
            token.append(advance())
        }
        return classifyAtom(token)
    }

    private func classifyAtom(_ token: String) -> Value {
        parseNumber(token, radix: 10) ?? .symbol(token)
    }
}

private let radixPrefixes: [Character: Int] = ["x": 16, "b": 2, "o": 8, "d": 10]

func parseNumber(_ token: String, radix: Int) -> Value? {
    if let integer = exactInteger(token, radix: radix) { return normalizeBig(integer) }
    if let slash = token.firstIndex(of: "/") {
        let denText = String(token[token.index(after: slash)...])
        guard let first = denText.first, first != "+", first != "-",
              let num = exactInteger(String(token[..<slash]), radix: radix),
              let den = exactInteger(denText, radix: radix),
              !den.isZero else { return nil }
        return makeRatio(num, den)
    }
    if radix == 10, let d = parseReal(token) { return .real(d) }
    return nil
}

private func exactInteger(_ text: String, radix: Int) -> BigInt? {
    if let small = Int(text, radix: radix) { return BigInt(small) }
    return BigInt(string: text, radix: radix)
}

func parseReal(_ token: String) -> Double? {
    if token.isEmpty { return nil }
    let first = token.first!
    let looksNumeric = first.isNumber || first == "+" || first == "-" || first == "."
    guard looksNumeric else { return nil }
    let hasDigit = token.contains(where: { $0.isNumber })
    guard hasDigit else { return nil }
    return Double(token)
}
