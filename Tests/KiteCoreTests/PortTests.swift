import XCTest
@testable import KiteCore

final class PortTests: XCTestCase {
    private func evalShow(_ src: String) throws -> String {
        writeString(try Interpreter().evalString(src))
    }

    func testStringOutputPort() throws {
        let program = """
        (define out (open-output-string))
        (write 'symbol out)
        (display " and " out)
        (write "quoted" out)
        (write-char #\\! out)
        (newline out)
        (write-string "tail" out)
        (get-output-string out)
        """
        XCTAssertEqual(try evalShow(program), "\"symbol and \\\"quoted\\\"!\\ntail\"")
    }

    func testStringInputPort() throws {
        let program = """
        (define in (open-input-string "ab\\nsecond line\\n(1 2) last"))
        (list (read-char in) (peek-char in) (read-char in) (read-line in)
              (read-line in) (read in) (read in) (eof-object? (read in)) (eof-object? (read-char in)))
        """
        XCTAssertEqual(try evalShow(program), "(#\\a #\\b #\\b \"\" \"second line\" (1 2) last #t #t)")
    }

    func testReadString() throws {
        XCTAssertEqual(try evalShow("(let ((p (open-input-string \"hello\"))) (list (read-string 2 p) (read-string 10 p) (eof-object? (read-string 1 p))))"), "(\"he\" \"llo\" #t)")
    }

    func testCallWithOutputString() throws {
        XCTAssertEqual(try evalShow("(call-with-output-string (lambda (port) (display (list 1 2) port)))"), "\"(1 2)\"")
    }

    func testCurrentOutputPortReachesInterpreterOutput() throws {
        let interp = Interpreter()
        var captured = ""
        interp.output = { captured += $0 }
        try interp.evalString("(display \"to port\" (current-output-port)) (write-char #\\. (current-output-port)) (newline)")
        XCTAssertEqual(captured, "to port.\n")
    }

    func testPortPredicatesAndClosing() throws {
        let program = """
        (define in (open-input-string "x"))
        (define out (open-output-string))
        (define before (list (port? in) (input-port? in) (output-port? in) (output-port? out) (input-port-open? in)))
        (close-port in)
        (list before (input-port-open? in))
        """
        XCTAssertEqual(try evalShow(program), "((#t #t #f #t #t) #f)")
        XCTAssertThrowsError(try evalShow("(let ((p (open-input-string \"x\"))) (close-input-port p) (read-char p))"))
        XCTAssertThrowsError(try evalShow("(read-char (open-output-string))"))
    }

    func testReadParsesFullSyntax() throws {
        XCTAssertEqual(try evalShow("(read (open-input-string \"#(1 [2 3] #xff 99999999999999999999)\"))"), "#(1 (2 3) 255 99999999999999999999)")
    }
}
