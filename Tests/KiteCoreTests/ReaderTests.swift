import XCTest
@testable import KiteCore

final class ReaderTests: XCTestCase {
    private func readOne(_ src: String) throws -> Value {
        let forms = try Reader(src).readProgram()
        XCTAssertEqual(forms.count, 1)
        return forms[0]
    }

    func testIntegerAndReal() throws {
        XCTAssertEqual(displayString(try readOne("42")), "42")
        XCTAssertEqual(displayString(try readOne("-7")), "-7")
        XCTAssertEqual(displayString(try readOne("3.5")), "3.5")
    }

    func testRational() throws {
        XCTAssertEqual(displayString(try readOne("3/2")), "3/2")
        XCTAssertEqual(displayString(try readOne("6/2")), "3")
    }

    func testStringAndChar() throws {
        XCTAssertEqual(writeString(try readOne("\"hi\\nthere\"")), "\"hi\\nthere\"")
        XCTAssertEqual(writeString(try readOne("#\\a")), "#\\a")
        XCTAssertEqual(writeString(try readOne("#\\space")), "#\\space")
        XCTAssertEqual(writeString(try readOne("#\\newline")), "#\\newline")
    }

    func testBooleans() throws {
        if case .bool(true) = try readOne("#t") {} else { XCTFail("not #t") }
        if case .bool(false) = try readOne("#f") {} else { XCTFail("not #f") }
    }

    func testListAndDotted() throws {
        XCTAssertEqual(writeString(try readOne("(1 2 3)")), "(1 2 3)")
        XCTAssertEqual(writeString(try readOne("(1 . 2)")), "(1 . 2)")
        XCTAssertEqual(writeString(try readOne("(a (b c) d)")), "(a (b c) d)")
    }

    func testQuoteSugar() throws {
        XCTAssertEqual(writeString(try readOne("'x")), "(quote x)")
        XCTAssertEqual(writeString(try readOne("`x")), "(quasiquote x)")
        XCTAssertEqual(writeString(try readOne(",x")), "(unquote x)")
        XCTAssertEqual(writeString(try readOne(",@x")), "(unquote-splicing x)")
    }

    func testSquareBracketsDelimitAtoms() throws {
        XCTAssertEqual(writeString(try readOne("[a b]")), "(a b)")
        XCTAssertEqual(writeString(try readOne("(let ([x 1] [y 2]) (+ x y))")), "(let ((x 1) (y 2)) (+ x y))")
        XCTAssertEqual(displayString(try Interpreter().evalString("(let ([x 1] [y 2]) (+ x y))")), "3")
    }

    func testVectorLiteral() throws {
        XCTAssertEqual(writeString(try readOne("#(1 #(2) \"s\")")), "#(1 #(2) \"s\")")
        if case .vector(let v) = try readOne("#()") { XCTAssertTrue(v.items.isEmpty) } else { XCTFail("not a vector") }
    }

    func testIntegersBeyondSixtyFourBits() throws {
        XCTAssertEqual(displayString(try readOne("123456789012345678901234567890")), "123456789012345678901234567890")
        XCTAssertEqual(displayString(try readOne("-9223372036854775809")), "-9223372036854775809")
        XCTAssertEqual(displayString(try readOne("100000000000000000000/3")), "100000000000000000000/3")
        if case .integer(let n) = try readOne("9223372036854775807") { XCTAssertEqual(n, Int.max) } else { XCTFail("not a fixnum") }
        if case .bigint = try readOne("9223372036854775808") {} else { XCTFail("not a bigint") }
    }

    func testRadixPrefixes() throws {
        XCTAssertEqual(displayString(try readOne("#xff")), "255")
        XCTAssertEqual(displayString(try readOne("#b-101")), "-5")
        XCTAssertEqual(displayString(try readOne("#o17")), "15")
        XCTAssertEqual(displayString(try readOne("#x10000000000000000")), "18446744073709551616")
        XCTAssertThrowsError(try readOne("#b102"))
    }

    func testSymbolsThatLookNumeric() throws {
        for token in ["+", "-", "...", "1+", "-x", "a/b", "1/-2"] {
            if case .symbol(let s) = try readOne(token) { XCTAssertEqual(s, token) } else { XCTFail("\(token) is not a symbol") }
        }
    }

    func testComments() throws {
        let forms = try Reader("; a comment\n(+ 1 2) #| block |# 5 #;(ignored) 9").readProgram()
        XCTAssertEqual(forms.count, 3)
        XCTAssertEqual(writeString(forms[0]), "(+ 1 2)")
        XCTAssertEqual(displayString(forms[1]), "5")
        XCTAssertEqual(displayString(forms[2]), "9")
    }
}
