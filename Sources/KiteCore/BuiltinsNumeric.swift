import Foundation

func installNumeric(_ r: BuiltinRegistry) {
    r.def("+", .atLeast(0)) { args in
        numToValue(try args.reduce(Num.int(0)) { numAdd($0, try asNum($1, "+")) })
    }
    r.def("*", .atLeast(0)) { args in
        numToValue(try args.reduce(Num.int(1)) { numMul($0, try asNum($1, "*")) })
    }
    r.def("-", .atLeast(1)) { args in
        let first = try asNum(args[0], "-")
        if args.count == 1 { return numToValue(numSub(.int(0), first)) }
        return numToValue(try args.dropFirst().reduce(first) { numSub($0, try asNum($1, "-")) })
    }
    r.def("/", .atLeast(1)) { args in
        let first = try asNum(args[0], "/")
        if args.count == 1 { return numToValue(try numDiv(.int(1), first)) }
        return numToValue(try args.dropFirst().reduce(first) { try numDiv($0, try asNum($1, "/")) })
    }

    func chainCompare(_ name: String, _ holds: @escaping (Int) -> Bool) {
        r.def(name, .atLeast(1)) { args in
            let nums = try args.map { try asNum($0, name) }
            return .bool(zip(nums, nums.dropFirst()).allSatisfy { holds(numCompare($0, $1)) })
        }
    }
    chainCompare("=") { $0 == 0 }
    chainCompare("<") { $0 < 0 }
    chainCompare(">") { $0 > 0 }
    chainCompare("<=") { $0 <= 0 }
    chainCompare(">=") { $0 >= 0 }

    func integerDivision(_ name: String, _ op: @escaping (BigInt, BigInt) -> BigInt) {
        r.def(name, .exactly(2)) { args in
            let a = try exactIntegerArg(args[0], name)
            let b = try exactIntegerArg(args[1], name)
            if b.isZero { throw schemeError("\(name): division by zero") }
            return normalizeBig(op(a, b))
        }
    }
    integerDivision("quotient") { $0.quotient($1) }
    integerDivision("remainder") { $0.remainder($1) }
    integerDivision("modulo") { $0.modulo($1) }
    integerDivision("truncate-quotient") { $0.quotient($1) }
    integerDivision("truncate-remainder") { $0.remainder($1) }
    integerDivision("floor-remainder") { $0.modulo($1) }
    integerDivision("floor-quotient") { a, b in (a - a.modulo(b)).quotient(b) }

    func pairedDivision(_ name: String, _ op: @escaping (BigInt, BigInt) -> (BigInt, BigInt)) {
        r.def(name, .exactly(2)) { args in
            let a = try exactIntegerArg(args[0], name)
            let b = try exactIntegerArg(args[1], name)
            if b.isZero { throw schemeError("\(name): division by zero") }
            let (q, rem) = op(a, b)
            return .values([normalizeBig(q), normalizeBig(rem)])
        }
    }
    pairedDivision("truncate/") { ($0.quotient($1), $0.remainder($1)) }
    pairedDivision("floor/") { a, b in
        let m = a.modulo(b)
        return ((a - m).quotient(b), m)
    }

    r.def("gcd", .atLeast(0)) { args in
        normalizeBig(try args.reduce(BigInt.zero) { BigInt.gcd($0, try exactIntegerArg($1, "gcd")) })
    }
    r.def("lcm", .atLeast(0)) { args in
        normalizeBig(try args.reduce(BigInt.one) { acc, value in
            let n = try exactIntegerArg(value, "lcm").magnitude
            if n.isZero || acc.isZero { return .zero }
            return (acc * n).quotient(BigInt.gcd(acc, n))
        })
    }
    r.def("abs", .exactly(1)) { args in
        let n = try asNum(args[0], "abs")
        return numCompare(n, .int(0)) < 0 ? numToValue(numSub(.int(0), n)) : args[0]
    }
    r.def("min", .atLeast(1)) { args in try extremum(args, "min") { $0 < 0 } }
    r.def("max", .atLeast(1)) { args in try extremum(args, "max") { $0 > 0 } }
    r.def("square", .exactly(1)) { args in
        let n = try asNum(args[0], "square")
        return numToValue(numMul(n, n))
    }
    r.def("expt", .exactly(2)) { args in try expt(args[0], args[1]) }
    r.def("1+", .exactly(1)) { args in numToValue(numAdd(try asNum(args[0], "1+"), .int(1))) }
    r.def("1-", .exactly(1)) { args in numToValue(numSub(try asNum(args[0], "1-"), .int(1))) }

    r.def("zero?", .exactly(1)) { args in .bool(numCompare(try asNum(args[0], "zero?"), .int(0)) == 0) }
    r.def("positive?", .exactly(1)) { args in .bool(numCompare(try asNum(args[0], "positive?"), .int(0)) > 0) }
    r.def("negative?", .exactly(1)) { args in .bool(numCompare(try asNum(args[0], "negative?"), .int(0)) < 0) }
    r.def("even?", .exactly(1)) { args in .bool(try exactIntegerArg(args[0], "even?").isEven) }
    r.def("odd?", .exactly(1)) { args in .bool(!(try exactIntegerArg(args[0], "odd?").isEven)) }

    r.predicate("number?") { isNumber($0) }
    r.predicate("complex?") { isNumber($0) }
    r.predicate("real?") { isNumber($0) }
    r.predicate("rational?") { value in
        if case .real(let d) = value { return d.isFinite }
        return isNumber(value)
    }
    r.predicate("integer?") { value in
        switch value {
        case .integer, .bigint: return true
        case .real(let d): return d.isFinite && d == d.rounded()
        default: return false
        }
    }
    r.predicate("exact-integer?") { bigFrom($0) != nil }
    r.def("exact?", .exactly(1)) { args in
        if case .real = try asNum(args[0], "exact?") { return .bool(false) }
        return .bool(true)
    }
    r.def("inexact?", .exactly(1)) { args in
        if case .real = try asNum(args[0], "inexact?") { return .bool(true) }
        return .bool(false)
    }

    for name in ["exact->inexact", "inexact"] {
        r.def(name, .exactly(1)) { args in .real(numToDouble(try asNum(args[0], name))) }
    }
    for name in ["inexact->exact", "exact"] {
        r.def(name, .exactly(1)) { args in
            guard case .real(let d) = try asNum(args[0], name) else { return args[0] }
            guard d.isFinite else { throw schemeError("\(name): no exact representation", [args[0]]) }
            return exactFromDouble(d)
        }
    }
    r.def("numerator", .exactly(1)) { args in
        switch try asNum(args[0], "numerator") {
        case .rat(let n, _): return normalizeBig(n)
        case .real(let d): return .real(numToDouble(try asNum(numeratorOf(exactFromDouble(d)), "numerator")))
        default: return args[0]
        }
    }
    r.def("denominator", .exactly(1)) { args in
        switch try asNum(args[0], "denominator") {
        case .rat(_, let d): return normalizeBig(d)
        case .real(let d): return .real(numToDouble(try asNum(denominatorOf(exactFromDouble(d)), "denominator")))
        default: return .integer(1)
        }
    }

    func rounding(_ name: String, _ mode: FloatingPointRoundingRule) {
        r.def(name, .exactly(1)) { args in
            switch try asNum(args[0], name) {
            case .real(let d): return .real(d.rounded(mode))
            case .rat(let n, let d): return normalizeBig(roundRatio(n, d, mode))
            default: return args[0]
            }
        }
    }
    rounding("floor", .down)
    rounding("ceiling", .up)
    rounding("truncate", .towardZero)
    rounding("round", .toNearestOrEven)

    r.def("sqrt", .exactly(1)) { args in
        let n = try asNum(args[0], "sqrt")
        if let exact = exactSquareRoot(n) { return exact }
        return .real(numToDouble(n).squareRoot())
    }
    r.def("exact-integer-sqrt", .exactly(1)) { args in
        let n = try exactIntegerArg(args[0], "exact-integer-sqrt")
        if n.isNegative { throw schemeError("exact-integer-sqrt: negative argument", [args[0]]) }
        let root = n.isqrt()
        return .values([normalizeBig(root), normalizeBig(n - root * root)])
    }

    r.def("number->string", .between(1, 2)) { args in
        let radix = args.count > 1 ? try radixArg(args[1], "number->string") : 10
        switch try asNum(args[0], "number->string") {
        case .int(let i): return .string(String(i, radix: radix))
        case .big(let b): return .string(b.toString(radix: radix))
        case .rat(let n, let d): return .string(n.toString(radix: radix) + "/" + d.toString(radix: radix))
        case .real(let d):
            guard radix == 10 else { throw schemeError("number->string: reals only in radix 10") }
            return .string(formatReal(d))
        }
    }
    r.def("string->number", .between(1, 2)) { args in
        let radix = args.count > 1 ? try radixArg(args[1], "string->number") : 10
        return parseNumber(try stringArg(args[0], "string->number"), radix: radix) ?? .bool(false)
    }
}

private func isNumber(_ value: Value) -> Bool {
    switch value {
    case .integer, .bigint, .rational, .real: return true
    default: return false
    }
}

private func radixArg(_ value: Value, _ who: String) throws -> Int {
    let radix = try intArg(value, who)
    guard [2, 8, 10, 16].contains(radix) else { throw schemeError("\(who): unsupported radix", [value]) }
    return radix
}

private func extremum(_ args: [Value], _ who: String, _ better: (Int) -> Bool) throws -> Value {
    var best = try asNum(args[0], who)
    var inexact = false
    for arg in args {
        let n = try asNum(arg, who)
        if case .real = n { inexact = true }
        if better(numCompare(n, best)) { best = n }
    }
    return inexact ? .real(numToDouble(best)) : numToValue(best)
}

private func numeratorOf(_ value: Value) -> Value {
    if case .rational(let n, _) = value { return normalizeBig(n) }
    return value
}

private func denominatorOf(_ value: Value) -> Value {
    if case .rational(_, let d) = value { return normalizeBig(d) }
    return .integer(1)
}

private func roundRatio(_ n: BigInt, _ d: BigInt, _ mode: FloatingPointRoundingRule) -> BigInt {
    let floor = (n - n.modulo(d)).quotient(d)
    let remainder = n - floor * d
    switch mode {
    case .down:
        return floor
    case .up:
        return floor + .one
    case .towardZero:
        return n.isNegative ? floor + .one : floor
    default:
        let twice = remainder + remainder
        if twice < d { return floor }
        if d < twice { return floor + .one }
        return floor.isEven ? floor : floor + .one
    }
}

private func exactSquareRoot(_ n: Num) -> Value? {
    func root(_ b: BigInt) -> BigInt? {
        if b.isNegative { return nil }
        let r = b.isqrt()
        return r * r == b ? r : nil
    }
    switch n {
    case .int(let i):
        return root(BigInt(i)).map(normalizeBig)
    case .big(let b):
        return root(b).map(normalizeBig)
    case .rat(let num, let den):
        guard let rn = root(num), let rd = root(den) else { return nil }
        return makeRatio(rn, rd)
    case .real:
        return nil
    }
}

private func expt(_ baseValue: Value, _ exponentValue: Value) throws -> Value {
    let base = try asNum(baseValue, "expt")
    let exponent = try asNum(exponentValue, "expt")
    if case .int(let e) = exponent, e > Int.min {
        switch base {
        case .int, .big, .rat:
            let (n, d) = exactRatio(base)
            if e >= 0 { return makeRatio(n.power(e), d.power(e)) }
            if n.isZero { throw schemeError("expt: division by zero") }
            return makeRatio(d.power(-e), n.power(-e))
        case .real(let x):
            return .real(pow(x, Double(e)))
        }
    }
    return .real(pow(numToDouble(base), numToDouble(exponent)))
}

private func exactRatio(_ n: Num) -> (BigInt, BigInt) {
    switch n {
    case .int(let i): return (BigInt(i), .one)
    case .big(let b): return (b, .one)
    case .rat(let a, let b): return (a, b)
    case .real: return (.zero, .one)
    }
}
