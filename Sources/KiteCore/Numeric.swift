enum Num {
    case int(Int)
    case big(BigInt)
    case rat(BigInt, BigInt)
    case real(Double)
}

func asNum(_ value: Value, _ who: String) throws -> Num {
    switch value {
    case .integer(let n): return .int(n)
    case .bigint(let b): return .big(b)
    case .rational(let n, let d): return .rat(n, d)
    case .real(let d): return .real(d)
    default: throw schemeError("\(who): expected number", [value])
    }
}

func numToDouble(_ n: Num) -> Double {
    switch n {
    case .int(let i): return Double(i)
    case .big(let b): return b.toDouble()
    case .rat(let a, let b): return a.toDouble() / b.toDouble()
    case .real(let d): return d
    }
}

func numToValue(_ n: Num) -> Value {
    switch n {
    case .int(let i): return .integer(i)
    case .big(let b): return normalizeBig(b)
    case .rat(let a, let b): return makeRatio(a, b)
    case .real(let d): return .real(d)
    }
}

func asNumFromValue(_ value: Value) -> Num {
    switch value {
    case .integer(let n): return .int(n)
    case .bigint(let b): return .big(b)
    case .rational(let n, let d): return .rat(n, d)
    case .real(let d): return .real(d)
    default: return .int(0)
    }
}

private func isReal(_ n: Num) -> Bool {
    if case .real = n { return true }
    return false
}

private func exactParts(_ n: Num) -> (BigInt, BigInt) {
    switch n {
    case .int(let i): return (BigInt(i), .one)
    case .big(let b): return (b, .one)
    case .rat(let a, let b): return (a, b)
    case .real: return (.zero, .one)
    }
}

private func reduceExact(_ numerator: BigInt, _ denominator: BigInt) -> Num {
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
    if den.isOne {
        return num.fitsInt ? .int(num.toInt()) : .big(num)
    }
    return .rat(num, den)
}

func numAdd(_ a: Num, _ b: Num) -> Num {
    if case .int(let x) = a, case .int(let y) = b {
        let (r, over) = x.addingReportingOverflow(y)
        return over ? .big(BigInt(x) + BigInt(y)) : .int(r)
    }
    if isReal(a) || isReal(b) {
        return .real(numToDouble(a) + numToDouble(b))
    }
    let (an, ad) = exactParts(a)
    let (bn, bd) = exactParts(b)
    return reduceExact(an * bd + bn * ad, ad * bd)
}

func numSub(_ a: Num, _ b: Num) -> Num {
    if case .int(let x) = a, case .int(let y) = b {
        let (r, over) = x.subtractingReportingOverflow(y)
        return over ? .big(BigInt(x) - BigInt(y)) : .int(r)
    }
    if isReal(a) || isReal(b) {
        return .real(numToDouble(a) - numToDouble(b))
    }
    let (an, ad) = exactParts(a)
    let (bn, bd) = exactParts(b)
    return reduceExact(an * bd - bn * ad, ad * bd)
}

func numMul(_ a: Num, _ b: Num) -> Num {
    if case .int(let x) = a, case .int(let y) = b {
        let (r, over) = x.multipliedReportingOverflow(by: y)
        return over ? .big(BigInt(x) * BigInt(y)) : .int(r)
    }
    if isReal(a) || isReal(b) {
        return .real(numToDouble(a) * numToDouble(b))
    }
    let (an, ad) = exactParts(a)
    let (bn, bd) = exactParts(b)
    return reduceExact(an * bn, ad * bd)
}

func numDiv(_ a: Num, _ b: Num) throws -> Num {
    if isReal(a) || isReal(b) {
        return .real(numToDouble(a) / numToDouble(b))
    }
    let (an, ad) = exactParts(a)
    let (bn, bd) = exactParts(b)
    if bn.isZero { throw schemeError("division by zero") }
    return reduceExact(an * bd, ad * bn)
}

func numCompare(_ a: Num, _ b: Num) -> Int {
    if case .int(let x) = a, case .int(let y) = b {
        return x == y ? 0 : (x < y ? -1 : 1)
    }
    if isReal(a) || isReal(b) {
        let x = numToDouble(a)
        let y = numToDouble(b)
        return x == y ? 0 : (x < y ? -1 : 1)
    }
    let (an, ad) = exactParts(a)
    let (bn, bd) = exactParts(b)
    let left = an * bd
    let right = bn * ad
    if left == right { return 0 }
    return left < right ? -1 : 1
}

func asExactInteger(_ value: Value, _ who: String) throws -> BigInt {
    switch value {
    case .integer(let n): return BigInt(n)
    case .bigint(let b): return b
    case .real(let d) where d == d.rounded() && d.isFinite:
        return exactIntegerFromDouble(d)
    default:
        throw schemeError("\(who): expected integer", [value])
    }
}

func exactIntegerFromDouble(_ d: Double) -> BigInt {
    if d == 0 { return .zero }
    let negative = d < 0
    var magnitude = abs(d)
    var result = BigInt.zero
    let chunk = 4294967296.0
    var scale = BigInt.one
    while magnitude >= 1 {
        let low = magnitude.truncatingRemainder(dividingBy: chunk)
        result = result + BigInt(Int(low)) * scale
        magnitude = (magnitude - low) / chunk
        scale = scale * BigInt(Int(chunk))
    }
    return negative ? result.negated : result
}

func exactFromDouble(_ d: Double) -> Value {
    if d == d.rounded() && abs(d) < 9.007199254740992e15 {
        return .integer(Int(d))
    }
    if d == d.rounded() {
        return normalizeBig(exactIntegerFromDouble(d))
    }
    let bits = d.bitPattern
    let sign = (bits >> 63) == 1
    let exponent = Int((bits >> 52) & 0x7ff)
    let fractionBits = bits & 0xf_ffff_ffff_ffff
    var mantissa: BigInt
    var twoExponent: Int
    if exponent == 0 {
        mantissa = BigInt(Int(fractionBits))
        twoExponent = -1074
    } else {
        mantissa = BigInt(Int(fractionBits | 0x10_0000_0000_0000))
        twoExponent = exponent - 1075
    }
    if sign { mantissa = mantissa.negated }
    if twoExponent >= 0 {
        return normalizeBig(mantissa * BigInt(2).power(twoExponent))
    }
    return makeRatio(mantissa, BigInt(2).power(-twoExponent))
}
