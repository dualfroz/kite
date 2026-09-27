import XCTest
@testable import KiteCore

final class NumericTests: XCTestCase {
    private func evalShow(_ src: String) throws -> String {
        writeString(try Interpreter().evalString(src))
    }

    func testOverflowPromotesToBigInt() throws {
        XCTAssertEqual(try evalShow("(* 99999999999 99999999999)"), "9999999999800000000001")
        XCTAssertEqual(try evalShow("(- (* 99999999999 99999999999) 9999999999800000000000)"), "1")
        XCTAssertEqual(try evalShow("(integer? (* 99999999999 99999999999))"), "#t")
        XCTAssertEqual(try evalShow("(exact-integer? (expt 2 80))"), "#t")
    }

    func testIntegerDivisionOnBigInts() throws {
        let big = "123456789012345678901234567890"
        XCTAssertEqual(try evalShow("(modulo \(big) 7)"), "0")
        XCTAssertEqual(try evalShow("(modulo (- \(big)) 11)"), "4")
        XCTAssertEqual(try evalShow("(remainder (- \(big)) 11)"), "-7")
        XCTAssertEqual(try evalShow("(quotient \(big) 1000000000000000000000)"), "123456789")
        XCTAssertEqual(try evalShow("(quotient (- (expt 2 63)) -1)"), "9223372036854775808")
    }

    func testParityAndGcdOnBigInts() throws {
        XCTAssertEqual(try evalShow("(list (even? (expt 2 70)) (odd? (+ (expt 2 70) 1)))"), "(#t #t)")
        XCTAssertEqual(try evalShow("(gcd (expt 2 100) (expt 6 50))"), "1125899906842624")
        XCTAssertEqual(try evalShow("(lcm 4 6 10)"), "60")
        XCTAssertEqual(try evalShow("(abs (- (expt 10 20)))"), "100000000000000000000")
    }

    func testExactExpt() throws {
        XCTAssertEqual(try evalShow("(expt 2 100)"), "1267650600228229401496703205376")
        XCTAssertEqual(try evalShow("(expt 2 -3)"), "1/8")
        XCTAssertEqual(try evalShow("(expt 2/3 3)"), "8/27")
        XCTAssertEqual(try evalShow("(expt 2.0 3)"), "8.0")
        XCTAssertEqual(try evalShow("(expt 4 1/2)"), "2.0")
    }

    func testRoundingAndParts() throws {
        XCTAssertEqual(try evalShow("(list (floor -7/2) (ceiling -7/2) (truncate -7/2) (round -7/2))"), "(-4 -3 -3 -4)")
        XCTAssertEqual(try evalShow("(list (round 5/2) (round 7/2) (round 2.5) (floor 2.7))"), "(2 4 2.0 2.0)")
        XCTAssertEqual(try evalShow("(list (numerator 6/4) (denominator 6/4) (denominator 5))"), "(3 2 1)")
    }

    func testExactness() throws {
        XCTAssertEqual(try evalShow("(exact 2.5)"), "5/2")
        XCTAssertEqual(try evalShow("(inexact->exact 4.0)"), "4")
        XCTAssertEqual(try evalShow("(exact->inexact 1/4)"), "0.25")
        XCTAssertEqual(try evalShow("(list (exact? 1/2) (inexact? 0.5) (exact? 0.5))"), "(#t #t #f)")
    }

    func testSquareRoots() throws {
        XCTAssertEqual(try evalShow("(sqrt 144)"), "12")
        XCTAssertEqual(try evalShow("(sqrt 9/16)"), "3/4")
        XCTAssertEqual(try evalShow("(sqrt 2)"), "1.4142135623730951")
        XCTAssertEqual(try evalShow("(sqrt (expt 10 40))"), "100000000000000000000")
        XCTAssertEqual(try evalShow("(call-with-values (lambda () (exact-integer-sqrt 17)) list)"), "(4 1)")
    }

    func testRadixConversion() throws {
        XCTAssertEqual(try evalShow("(number->string 255 16)"), "\"ff\"")
        XCTAssertEqual(try evalShow("(number->string (expt 2 70) 2)"), "\"1" + String(repeating: "0", count: 70) + "\"")
        XCTAssertEqual(try evalShow("(string->number \"101\" 2)"), "5")
        XCTAssertEqual(try evalShow("(string->number \"123456789012345678901234567890\")"), "123456789012345678901234567890")
        XCTAssertEqual(try evalShow("(string->number \"nope\")"), "#f")
    }

    func testMinMaxContagion() throws {
        XCTAssertEqual(try evalShow("(max 1 2.0)"), "2.0")
        XCTAssertEqual(try evalShow("(min 1/2 1/3)"), "1/3")
    }

    func testDivisionByZero() {
        XCTAssertThrowsError(try evalShow("(modulo (expt 2 70) 0)"))
        XCTAssertThrowsError(try evalShow("(/ 1 0)"))
    }
}
