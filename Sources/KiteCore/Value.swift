public final class Pair {
    public var car: Value
    public var cdr: Value
    public init(_ car: Value, _ cdr: Value) {
        self.car = car
        self.cdr = cdr
    }
}

public final class Lambda {
    public let params: [String]
    public let rest: String?
    public let body: [Value]
    public let env: Environment
    public var name: String
    init(params: [String], rest: String?, body: [Value], env: Environment, name: String) {
        self.params = params
        self.rest = rest
        self.body = body
        self.env = env
        self.name = name
    }
}

public enum SpecialKind {
    case none
    case apply
    case callCC
    case withExceptionHandler
    case dynamicWind
    case values
    case callWithValues
}

public final class VectorRef {
    public var items: [Value]
    public init(_ items: [Value]) {
        self.items = items
    }
}

public final class ErrorObject {
    public let message: String
    public let irritants: [Value]
    public let kind: String
    public init(message: String, irritants: [Value], kind: String = "error") {
        self.message = message
        self.irritants = irritants
        self.kind = kind
    }
}

public final class Promise {
    public var forced: Bool
    public var value: Value
    public var thunk: Value
    public init(thunk: Value) {
        self.forced = false
        self.value = .unspecified
        self.thunk = thunk
    }
}

public final class Builtin {
    public let name: String
    public let special: SpecialKind
    public let fn: ([Value]) throws -> Value
    init(name: String, special: SpecialKind = .none, fn: @escaping ([Value]) throws -> Value) {
        self.name = name
        self.special = special
        self.fn = fn
    }
}

public indirect enum Value {
    case null
    case bool(Bool)
    case integer(Int)
    case bigint(BigInt)
    case rational(BigInt, BigInt)
    case real(Double)
    case char(Character)
    case string(String)
    case symbol(String)
    case pair(Pair)
    case vector(VectorRef)
    case hashTable(HashTable)
    case port(Port)
    case errorObject(ErrorObject)
    case promise(Promise)
    case builtin(Builtin)
    case closure(Lambda)
    case continuation(Kont, [Winder], [Value])
    case values([Value])
    case syntax(SyntaxRules)
    case unspecified
    case eof
}

let hygieneMark: Character = "\u{1}"

func baseName(_ name: String) -> String {
    if let idx = name.firstIndex(of: hygieneMark) {
        return String(name[..<idx])
    }
    return name
}

func isTruthy(_ value: Value) -> Bool {
    if case .bool(false) = value { return false }
    return true
}

func cons(_ a: Value, _ d: Value) -> Value {
    .pair(Pair(a, d))
}

func arrayToList(_ items: [Value], tail: Value = .null) -> Value {
    var acc = tail
    for item in items.reversed() {
        acc = cons(item, acc)
    }
    return acc
}

func listToArray(_ value: Value) throws -> [Value] {
    var out: [Value] = []
    var cur = value
    while true {
        switch cur {
        case .null:
            return out
        case .pair(let p):
            out.append(p.car)
            cur = p.cdr
        default:
            throw schemeError("expected proper list", [value])
        }
    }
}

func listToArrayWithTail(_ value: Value) -> ([Value], Value) {
    var out: [Value] = []
    var cur = value
    while case .pair(let p) = cur {
        out.append(p.car)
        cur = p.cdr
    }
    return (out, cur)
}

func isProperList(_ value: Value) -> Bool {
    var slow = value
    var fast = value
    while true {
        if case .null = fast { return true }
        guard case .pair(let fp) = fast else { return false }
        fast = fp.cdr
        if case .null = fast { return true }
        guard case .pair(let fp2) = fast else { return false }
        fast = fp2.cdr
        guard case .pair(let sp) = slow else { return false }
        slow = sp.cdr
        if case .pair(let a) = fast, case .pair(let b) = slow, a === b { return false }
    }
}

func gcdInt(_ a: Int, _ b: Int) -> Int {
    var x = a == Int.min ? a : abs(a)
    var y = b == Int.min ? b : abs(b)
    x = x < 0 ? -(x + 1) &+ 1 : x
    y = y < 0 ? -(y + 1) &+ 1 : y
    while y != 0 {
        (x, y) = (y, x % y)
    }
    return x
}

func normalizeBig(_ value: BigInt) -> Value {
    value.fitsInt ? .integer(value.toInt()) : .bigint(value)
}

func bigFrom(_ value: Value) -> BigInt? {
    switch value {
    case .integer(let n): return BigInt(n)
    case .bigint(let b): return b
    default: return nil
    }
}

func makeRatio(_ numerator: BigInt, _ denominator: BigInt) -> Value {
    var num = numerator
    var den = denominator
    if den.isNegative {
        num = num.negated
        den = den.negated
    }
    let divisor = BigInt.gcd(num, den)
    if !divisor.isZero && !divisor.isOne {
        num = num.quotient(divisor)
        den = den.quotient(divisor)
    }
    if den.isOne { return normalizeBig(num) }
    return .rational(num, den)
}

func makeRational(_ n: Int, _ d: Int) -> Value {
    makeRatio(BigInt(n), BigInt(d))
}

func eqv(_ a: Value, _ b: Value) -> Bool {
    switch (a, b) {
    case (.null, .null): return true
    case (.unspecified, .unspecified): return true
    case (.eof, .eof): return true
    case (.bool(let x), .bool(let y)): return x == y
    case (.integer(let x), .integer(let y)): return x == y
    case (.bigint(let x), .bigint(let y)): return x == y
    case (.rational(let xn, let xd), .rational(let yn, let yd)): return xn == yn && xd == yd
    case (.real(let x), .real(let y)): return x == y
    case (.char(let x), .char(let y)): return x == y
    case (.symbol(let x), .symbol(let y)): return x == y
    case (.string(let x), .string(let y)): return x == y
    case (.pair(let x), .pair(let y)): return x === y
    case (.vector(let x), .vector(let y)): return x === y
    case (.hashTable(let x), .hashTable(let y)): return x === y
    case (.port(let x), .port(let y)): return x === y
    case (.errorObject(let x), .errorObject(let y)): return x === y
    case (.promise(let x), .promise(let y)): return x === y
    case (.closure(let x), .closure(let y)): return x === y
    case (.builtin(let x), .builtin(let y)): return x === y
    default: return false
    }
}

func equalValues(_ a: Value, _ b: Value) -> Bool {
    switch (a, b) {
    case (.pair(let x), .pair(let y)):
        return equalValues(x.car, y.car) && equalValues(x.cdr, y.cdr)
    case (.string(let x), .string(let y)):
        return x == y
    case (.vector(let x), .vector(let y)):
        if x.items.count != y.items.count { return false }
        for i in 0..<x.items.count where !equalValues(x.items[i], y.items[i]) { return false }
        return true
    default:
        return eqv(a, b)
    }
}

func schemeHash(_ value: Value, _ depth: Int = 0) -> Int {
    if depth > 12 { return 0 }
    switch value {
    case .null: return 1
    case .bool(let b): return b ? 2 : 3
    case .integer(let n): return n.hashValue
    case .bigint(let b): return b.hashValue
    case .rational(let n, let d): return n.hashValue ^ (d.hashValue &* 31)
    case .real(let d): return d.hashValue
    case .char(let c): return c.hashValue
    case .string(let s): return s.hashValue
    case .symbol(let s): return s.hashValue
    case .pair(let p):
        return (schemeHash(p.car, depth + 1) &* 31) &+ schemeHash(p.cdr, depth + 1) &+ 7
    case .vector(let v):
        var acc = 17
        for item in v.items.prefix(8) { acc = (acc &* 31) &+ schemeHash(item, depth + 1) }
        return acc
    case .eof: return 5
    case .unspecified: return 6
    default:
        return 0
    }
}
