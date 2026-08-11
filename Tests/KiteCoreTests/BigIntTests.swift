import XCTest
@testable import KiteCore

final class BigIntTests: XCTestCase {
    func testRoundTripInt() {
        for value in [0, 1, -1, 42, -42, Int.max, Int.min, 1234567890, -1234567890] {
            let big = BigInt(value)
            XCTAssertTrue(big.fitsInt, "\(value) should fit")
            XCTAssertEqual(big.toInt(), value)
        }
    }

    func testAddSubAgainstInt() {
        let pairs = [(12, 34), (-5, 9), (1000, -1000), (999999, 1), (-7, -8)]
        for (a, b) in pairs {
            XCTAssertEqual((BigInt(a) + BigInt(b)).toInt(), a + b)
            XCTAssertEqual((BigInt(a) - BigInt(b)).toInt(), a - b)
            XCTAssertEqual((BigInt(a) * BigInt(b)).toInt(), a * b)
        }
    }

    func testFactorialKnownValue() {
        var acc = BigInt.one
        for k in 1...100 { acc = acc * BigInt(k) }
        let expected = "93326215443944152681699238856266700490715968264381621468592963895217599993229915608941463976156518286253697920827223758251185210916864000000000000000000000000"
        XCTAssertEqual(acc.description, expected)
    }

    func testDivModAgainstInt() {
        let pairs = [(17, 5), (-17, 5), (17, -5), (-17, -5), (100, 7), (5, 17), (0, 3)]
        for (a, b) in pairs {
            let (q, r) = BigInt.divMod(BigInt(a), BigInt(b))
            XCTAssertEqual(q.toInt(), a / b, "quotient \(a)/\(b)")
            XCTAssertEqual(r.toInt(), a % b, "remainder \(a)%\(b)")
            XCTAssertEqual((q * BigInt(b) + r).toInt(), a, "identity \(a)/\(b)")
        }
    }

    func testBigDivMod() {
        var big = BigInt.one
        for k in 1...50 { big = big * BigInt(k) }
        let divisor = BigInt(string: "1000000000000000000", radix: 10)!
        let (q, r) = BigInt.divMod(big, divisor)
        XCTAssertEqual((q * divisor + r), big)
        XCTAssertTrue(r < divisor)
        XCTAssertFalse(r.isNegative)
    }

    func testModulo() {
        XCTAssertEqual(BigInt(-7).modulo(BigInt(3)).toInt(), 2)
        XCTAssertEqual(BigInt(7).modulo(BigInt(3)).toInt(), 1)
        XCTAssertEqual(BigInt(7).modulo(BigInt(-3)).toInt(), -2)
        XCTAssertEqual(BigInt(-7).modulo(BigInt(-3)).toInt(), -1)
    }

    func testGcd() {
        XCTAssertEqual(BigInt.gcd(BigInt(12), BigInt(18)).toInt(), 6)
        XCTAssertEqual(BigInt.gcd(BigInt(0), BigInt(5)).toInt(), 5)
        var a = BigInt.one
        for k in 1...30 { a = a * BigInt(k) }
        var b = BigInt.one
        for k in 1...20 { b = b * BigInt(k) }
        XCTAssertEqual(BigInt.gcd(a, b), b)
    }

    func testPower() {
        XCTAssertEqual(BigInt(2).power(10).toInt(), 1024)
        XCTAssertEqual(BigInt(2).power(64).description, "18446744073709551616")
        XCTAssertEqual(BigInt(10).power(30).description, "1000000000000000000000000000000")
    }

    func testStringRoundTrip() {
        let samples = [
            "0", "1", "-1", "255", "4294967296", "18446744073709551616",
            "-93326215443944152681699238856266700490715968264381621468592963895217599993229915608941463976156518286253697920827223758251185210916864000000000000000000000000",
        ]
        for s in samples {
            XCTAssertEqual(BigInt(string: s, radix: 10)?.description, s)
        }
    }

    func testRadixConversion() {
        XCTAssertEqual(BigInt(255).toString(radix: 16), "ff")
        XCTAssertEqual(BigInt(255).toString(radix: 2), "11111111")
        XCTAssertEqual(BigInt(string: "ff", radix: 16)?.toInt(), 255)
        XCTAssertEqual(BigInt(string: "-101", radix: 2)?.toInt(), -5)
        XCTAssertEqual(BigInt(1000000).toString(radix: 16), "f4240")
    }

    func testIsqrt() {
        XCTAssertEqual(BigInt(0).isqrt().toInt(), 0)
        XCTAssertEqual(BigInt(1).isqrt().toInt(), 1)
        XCTAssertEqual(BigInt(15).isqrt().toInt(), 3)
        XCTAssertEqual(BigInt(16).isqrt().toInt(), 4)
        XCTAssertEqual(BigInt(17).isqrt().toInt(), 4)
        let big = BigInt(string: "100000000000000000000", radix: 10)!
        XCTAssertEqual(big.isqrt().toInt(), 10000000000)
    }

    func testComparison() {
        XCTAssertTrue(BigInt(-5) < BigInt(3))
        XCTAssertTrue(BigInt(3) < BigInt(5))
        XCTAssertTrue(BigInt(string: "100000000000000000000", radix: 10)! > BigInt(Int.max))
        XCTAssertTrue(BigInt(Int.min) < BigInt(0))
    }
}
