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
    case raise
    case raiseContinuable
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
    public enum Kind {
        case general
        case read
        case file
    }

    public let message: String
    public let irritants: [Value]
    public let kind: Kind
    public init(message: String, irritants: [Value], kind: Kind = .general) {
        self.message = message
        self.irritants = irritants
        self.kind = kind
    }
}

final class PromiseState {
    var done: Bool
    var lazy: Bool
    var payload: Value

    init(done: Bool, lazy: Bool, payload: Value) {
        self.done = done
        self.lazy = lazy
        self.payload = payload
    }
}

public final class Promise {
    var state: PromiseState

    init(done: Bool, lazy: Bool, payload: Value) {
        self.state = PromiseState(done: done, lazy: lazy, payload: payload)
    }

    public static func resolved(_ value: Value) -> Promise {
        Promise(done: true, lazy: false, payload: value)
    }

    public var isForced: Bool { state.done }
}

public final class RecordType {
    public let name: String
    public let fields: [String]
    init(name: String, fields: [String]) {
        self.name = name
        self.fields = fields
    }
}

public final class Record {
    public let type: RecordType
    public var fields: [Value]
    init(type: RecordType, fields: [Value]) {
        self.type = type
        self.fields = fields
    }
}

public struct Arity {
    public let min: Int
    public let max: Int?

    public static func exactly(_ count: Int) -> Arity { Arity(min: count, max: count) }
    public static func atLeast(_ count: Int) -> Arity { Arity(min: count, max: nil) }
    public static func between(_ low: Int, _ high: Int) -> Arity { Arity(min: low, max: high) }

    func check(_ count: Int, _ who: String) throws {
        if count >= min, max.map({ count <= $0 }) ?? true { return }
        let expected: String
        switch max {
        case .some(let high) where high == min: expected = "\(min)"
        case .some(let high): expected = "\(min) to \(high)"
        case .none: expected = "at least \(min)"
        }
        throw schemeError("\(who): expected \(expected) argument\(expected == "1" ? "" : "s"), got \(count)")
    }
}

public final class Builtin {
    public let name: String
    public let special: SpecialKind
    public let arity: Arity
    public let fn: ([Value]) throws -> Value
    init(name: String, special: SpecialKind = .none, arity: Arity, fn: @escaping ([Value]) throws -> Value) {
        self.name = name
        self.special = special
        self.arity = arity
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
    case record(Record)
    case recordType(RecordType)
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
    case (.record(let x), .record(let y)): return x === y
    case (.recordType(let x), .recordType(let y)): return x === y
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

func identityHash(_ object: AnyObject) -> Int {
    ObjectIdentifier(object).hashValue
}

func schemeHash(_ value: Value, structural: Bool, _ depth: Int = 0) -> Int {
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
        guard structural else { return identityHash(p) }
        return (schemeHash(p.car, structural: true, depth + 1) &* 31)
            &+ schemeHash(p.cdr, structural: true, depth + 1) &+ 7
    case .vector(let v):
        guard structural else { return identityHash(v) }
        var acc = 17
        for element in v.items.prefix(8) {
            acc = (acc &* 31) &+ schemeHash(element, structural: true, depth + 1)
        }
        return acc
    case .hashTable(let h): return identityHash(h)
    case .port(let p): return identityHash(p)
    case .errorObject(let e): return identityHash(e)
    case .promise(let p): return identityHash(p)
    case .record(let r): return identityHash(r)
    case .recordType(let t): return identityHash(t)
    case .closure(let l): return identityHash(l)
    case .builtin(let b): return identityHash(b)
    case .eof: return 5
    case .unspecified: return 6
    case .continuation, .values, .syntax: return 0
    }
}
