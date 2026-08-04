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

    func testComments() throws {
        let forms = try Reader("; a comment\n(+ 1 2) #| block |# 5 #;(ignored) 9").readProgram()
        XCTAssertEqual(forms.count, 3)
        XCTAssertEqual(writeString(forms[0]), "(+ 1 2)")
        XCTAssertEqual(displayString(forms[1]), "5")
        XCTAssertEqual(displayString(forms[2]), "9")
    }
}
