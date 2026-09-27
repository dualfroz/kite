struct BuiltinRegistry {
    let env: Environment

    func def(_ name: String, _ arity: Arity, _ special: SpecialKind = .none,
             _ fn: @escaping ([Value]) throws -> Value = { _ in .unspecified }) {
        env.define(name, .builtin(Builtin(name: name, special: special, arity: arity, fn: fn)))
    }

    func predicate(_ name: String, _ test: @escaping (Value) -> Bool) {
        def(name, .exactly(1)) { args in .bool(test(args[0])) }
    }
}

func intArg(_ v: Value, _ who: String) throws -> Int {
    guard case .integer(let n) = v else { throw schemeError("\(who): expected fixnum", [v]) }
    return n
}

func indexArg(_ v: Value, _ who: String) throws -> Int {
    let n = try intArg(v, who)
    guard n >= 0 else { throw schemeError("\(who): expected non-negative index", [v]) }
    return n
}

func exactIntegerArg(_ v: Value, _ who: String) throws -> BigInt {
    guard let big = bigFrom(v) else { throw schemeError("\(who): expected exact integer", [v]) }
    return big
}

func stringArg(_ v: Value, _ who: String) throws -> String {
    guard case .string(let s) = v else { throw schemeError("\(who): expected string", [v]) }
    return s
}

func charArg(_ v: Value, _ who: String) throws -> Character {
    guard case .char(let c) = v else { throw schemeError("\(who): expected char", [v]) }
    return c
}

func symbolArg(_ v: Value, _ who: String) throws -> String {
    guard case .symbol(let s) = v else { throw schemeError("\(who): expected symbol", [v]) }
    return baseName(s)
}

func pairArg(_ v: Value, _ who: String) throws -> Pair {
    guard case .pair(let p) = v else { throw schemeError("\(who): expected pair", [v]) }
    return p
}

func vectorArg(_ v: Value, _ who: String) throws -> VectorRef {
    guard case .vector(let vec) = v else { throw schemeError("\(who): expected vector", [v]) }
    return vec
}

func hashTableArg(_ v: Value, _ who: String) throws -> HashTable {
    guard case .hashTable(let h) = v else { throw schemeError("\(who): expected hash table", [v]) }
    return h
}

func portArg(_ v: Value, _ who: String) throws -> Port {
    guard case .port(let p) = v else { throw schemeError("\(who): expected port", [v]) }
    return p
}

func promiseArg(_ v: Value, _ who: String) throws -> Promise {
    guard case .promise(let p) = v else { throw schemeError("\(who): expected promise", [v]) }
    return p
}

func errorObjectArg(_ v: Value, _ who: String) throws -> ErrorObject {
    guard case .errorObject(let e) = v else { throw schemeError("\(who): expected error object", [v]) }
    return e
}

func rangeArgs(_ args: [Value], from startIndex: Int, count: Int, _ who: String) throws -> Range<Int> {
    let start = args.count > startIndex ? try indexArg(args[startIndex], who) : 0
    let end = args.count > startIndex + 1 ? try indexArg(args[startIndex + 1], who) : count
    guard start <= end, end <= count else {
        throw schemeError("\(who): range \(start)..\(end) out of bounds for length \(count)")
    }
    return start..<end
}

func isProcedure(_ value: Value) -> Bool {
    switch value {
    case .builtin, .closure, .continuation: return true
    default: return false
    }
}
