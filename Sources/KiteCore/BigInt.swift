public struct BigInt: Equatable, Comparable, Hashable, CustomStringConvertible {
    public private(set) var negative: Bool
    public private(set) var mag: [UInt32]

    public init(negative: Bool, mag: [UInt32]) {
        var trimmed = mag
        while let last = trimmed.last, last == 0 { trimmed.removeLast() }
        self.mag = trimmed
        self.negative = trimmed.isEmpty ? false : negative
    }

    public init(_ value: Int) {
        if value == 0 {
            self.negative = false
            self.mag = []
            return
        }
        let neg = value < 0
        var unsigned: UInt64 = neg ? (UInt64(~value) &+ 1) : UInt64(value)
        var limbs: [UInt32] = []
        while unsigned != 0 {
            limbs.append(UInt32(unsigned & 0xffff_ffff))
            unsigned >>= 32
        }
        self.negative = neg
        self.mag = limbs
    }

    public static let zero = BigInt(0)
    public static let one = BigInt(1)

    public var isZero: Bool { mag.isEmpty }
    public var isOne: Bool { !negative && mag.count == 1 && mag[0] == 1 }
    public var isNegative: Bool { negative }
    public var isEven: Bool { mag.isEmpty || (mag[0] & 1) == 0 }

    var lowUInt64: UInt64 {
        var v: UInt64 = 0
        if mag.count > 0 { v |= UInt64(mag[0]) }
        if mag.count > 1 { v |= UInt64(mag[1]) << 32 }
        return v
    }

    public var fitsInt: Bool {
        if mag.count > 2 { return false }
        let m = lowUInt64
        if negative { return m <= UInt64(Int.max) + 1 }
        return m <= UInt64(Int.max)
    }

    public func toInt() -> Int {
        let m = lowUInt64
        if negative {
            if m == UInt64(Int.max) + 1 { return Int.min }
            return -Int(m)
        }
        return Int(m)
    }

    public func toDouble() -> Double {
        var result = 0.0
        for limb in mag.reversed() {
            result = result * 4294967296.0 + Double(limb)
        }
        return negative ? -result : result
    }

    public var negated: BigInt {
        BigInt(negative: !negative, mag: mag)
    }

    public var magnitude: BigInt {
        BigInt(negative: false, mag: mag)
    }

    public static func == (lhs: BigInt, rhs: BigInt) -> Bool {
        lhs.negative == rhs.negative && lhs.mag == rhs.mag
    }

    public static func < (lhs: BigInt, rhs: BigInt) -> Bool {
        if lhs.negative != rhs.negative { return lhs.negative }
        let cmp = compareMagnitude(lhs.mag, rhs.mag)
        return lhs.negative ? cmp > 0 : cmp < 0
    }

    static func compareMagnitude(_ a: [UInt32], _ b: [UInt32]) -> Int {
        if a.count != b.count { return a.count < b.count ? -1 : 1 }
        var i = a.count - 1
        while i >= 0 {
            if a[i] != b[i] { return a[i] < b[i] ? -1 : 1 }
            i -= 1
        }
        return 0
    }

    static func addMagnitude(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        let (long, short) = a.count >= b.count ? (a, b) : (b, a)
        var out: [UInt32] = []
        out.reserveCapacity(long.count + 1)
        var carry: UInt64 = 0
        for i in 0..<long.count {
            var sum = UInt64(long[i]) + carry
            if i < short.count { sum += UInt64(short[i]) }
            out.append(UInt32(sum & 0xffff_ffff))
            carry = sum >> 32
        }
        if carry != 0 { out.append(UInt32(carry)) }
        return out
    }

    static func subMagnitude(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        var out: [UInt32] = []
        out.reserveCapacity(a.count)
        var borrow: Int64 = 0
        for i in 0..<a.count {
            var diff = Int64(a[i]) - borrow
            if i < b.count { diff -= Int64(b[i]) }
            if diff < 0 {
                diff += 0x1_0000_0000
                borrow = 1
            } else {
                borrow = 0
            }
            out.append(UInt32(diff))
        }
        while let last = out.last, last == 0 { out.removeLast() }
        return out
    }

    static func mulMagnitude(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        if a.isEmpty || b.isEmpty { return [] }
        var out = [UInt32](repeating: 0, count: a.count + b.count)
        for i in 0..<a.count {
            var carry: UInt64 = 0
            let ai = UInt64(a[i])
            for j in 0..<b.count {
                let idx = i + j
                let cur = UInt64(out[idx]) + ai * UInt64(b[j]) + carry
                out[idx] = UInt32(cur & 0xffff_ffff)
                carry = cur >> 32
            }
            out[i + b.count] = UInt32(carry)
        }
        while let last = out.last, last == 0 { out.removeLast() }
        return out
    }

    static func shiftLeftOne(_ a: [UInt32]) -> [UInt32] {
        var out: [UInt32] = []
        out.reserveCapacity(a.count + 1)
        var carry: UInt32 = 0
        for limb in a {
            let next = limb >> 31
            out.append((limb << 1) | carry)
            carry = next
        }
        if carry != 0 { out.append(carry) }
        return out
    }

    static func bitLength(_ a: [UInt32]) -> Int {
        guard let top = a.last else { return 0 }
        return (a.count - 1) * 32 + (32 - top.leadingZeroBitCount)
    }

    static func testBit(_ a: [UInt32], _ index: Int) -> Bool {
        let limb = index >> 5
        if limb >= a.count { return false }
        return (a[limb] >> UInt32(index & 31)) & 1 == 1
    }

    static func divModSmall(_ a: [UInt32], _ divisor: UInt32) -> ([UInt32], UInt32) {
        var quotient = [UInt32](repeating: 0, count: a.count)
        var remainder: UInt64 = 0
        var i = a.count - 1
        while i >= 0 {
            let cur = (remainder << 32) | UInt64(a[i])
            quotient[i] = UInt32(cur / UInt64(divisor))
            remainder = cur % UInt64(divisor)
            i -= 1
        }
        while let last = quotient.last, last == 0 { quotient.removeLast() }
        return (quotient, UInt32(remainder))
    }

    static func divModMagnitude(_ u: [UInt32], _ v: [UInt32]) -> ([UInt32], [UInt32]) {
        if compareMagnitude(u, v) < 0 { return ([], u) }
        if v.count == 1 {
            let (q, r) = divModSmall(u, v[0])
            return (q, r == 0 ? [] : [r])
        }
        let totalBits = bitLength(u)
        var quotient = [UInt32](repeating: 0, count: (totalBits + 31) / 32)
        var remainder: [UInt32] = []
        var i = totalBits - 1
        while i >= 0 {
            remainder = shiftLeftOne(remainder)
            if testBit(u, i) {
                if remainder.isEmpty { remainder = [1] } else { remainder[0] |= 1 }
            }
            if compareMagnitude(remainder, v) >= 0 {
                remainder = subMagnitude(remainder, v)
                quotient[i >> 5] |= (UInt32(1) << UInt32(i & 31))
            }
            i -= 1
        }
        while let last = quotient.last, last == 0 { quotient.removeLast() }
        return (quotient, remainder)
    }

    public static func + (lhs: BigInt, rhs: BigInt) -> BigInt {
        if lhs.negative == rhs.negative {
            return BigInt(negative: lhs.negative, mag: addMagnitude(lhs.mag, rhs.mag))
        }
        let cmp = compareMagnitude(lhs.mag, rhs.mag)
        if cmp == 0 { return .zero }
        if cmp > 0 {
            return BigInt(negative: lhs.negative, mag: subMagnitude(lhs.mag, rhs.mag))
        }
        return BigInt(negative: rhs.negative, mag: subMagnitude(rhs.mag, lhs.mag))
    }

    public static func - (lhs: BigInt, rhs: BigInt) -> BigInt {
        lhs + rhs.negated
    }

    public static func * (lhs: BigInt, rhs: BigInt) -> BigInt {
        BigInt(negative: lhs.negative != rhs.negative, mag: mulMagnitude(lhs.mag, rhs.mag))
    }

    public static func divMod(_ dividend: BigInt, _ divisor: BigInt) -> (quotient: BigInt, remainder: BigInt) {
        let (q, r) = divModMagnitude(dividend.mag, divisor.mag)
        let quotient = BigInt(negative: dividend.negative != divisor.negative, mag: q)
        let remainder = BigInt(negative: dividend.negative, mag: r)
        return (quotient, remainder)
    }

    public func quotient(_ other: BigInt) -> BigInt { BigInt.divMod(self, other).quotient }
    public func remainder(_ other: BigInt) -> BigInt { BigInt.divMod(self, other).remainder }

    public func modulo(_ other: BigInt) -> BigInt {
        let r = remainder(other)
        if r.isZero { return r }
        if r.negative != other.negative { return r + other }
        return r
    }
}
