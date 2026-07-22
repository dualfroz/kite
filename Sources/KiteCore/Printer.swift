public func displayString(_ value: Value) -> String {
    render(value, write: false)
}

public func writeString(_ value: Value) -> String {
    render(value, write: true)
}

func formatReal(_ d: Double) -> String {
    if d.isNaN { return "+nan.0" }
    if d.isInfinite { return d > 0 ? "+inf.0" : "-inf.0" }
    if d == d.rounded() && abs(d) < 1e15 {
        return String(format: "%.1f", d)
    }
    return String(d)
}

private func render(_ value: Value, write: Bool) -> String {
    switch value {
    case .null:
        return "()"
    case .bool(let b):
        return b ? "#t" : "#f"
    case .integer(let n):
        return String(n)
    case .rational(let n, let d):
        return "\(n)/\(d)"
    case .real(let d):
        return formatReal(d)
    case .char(let c):
        if write { return writeChar(c) }
        return String(c)
    case .string(let s):
        if write { return "\"" + escapeString(s) + "\"" }
        return s
    case .symbol(let s):
        return baseName(s)
    case .pair:
        return renderList(value, write: write)
    case .builtin(let b):
        return "#<procedure:\(b.name)>"
    case .closure(let l):
        return "#<procedure:\(l.name)>"
    case .continuation:
        return "#<continuation>"
    case .syntax:
        return "#<syntax>"
    case .unspecified:
        return ""
    case .eof:
        return "#<eof>"
    }
}

private func renderList(_ value: Value, write: Bool) -> String {
    var parts: [String] = []
    var cur = value
    while case .pair(let p) = cur {
        parts.append(render(p.car, write: write))
        cur = p.cdr
    }
    if case .null = cur {
        return "(" + parts.joined(separator: " ") + ")"
    }
    return "(" + parts.joined(separator: " ") + " . " + render(cur, write: write) + ")"
}

private func writeChar(_ c: Character) -> String {
    switch c {
    case " ": return "#\\space"
    case "\n": return "#\\newline"
    case "\t": return "#\\tab"
    case "\r": return "#\\return"
    case "\u{0}": return "#\\null"
    default: return "#\\\(c)"
    }
}

private func escapeString(_ s: String) -> String {
    var out = ""
    for c in s {
        switch c {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\t": out += "\\t"
        case "\r": out += "\\r"
        default: out.append(c)
        }
    }
    return out
}
