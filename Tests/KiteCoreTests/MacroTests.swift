import XCTest
@testable import KiteCore

final class MacroTests: XCTestCase {
    private func evalShow(_ src: String) throws -> String {
        displayString(try Interpreter().evalString(src))
    }

    func testWhenUnlessFromPrelude() throws {
        XCTAssertEqual(try evalShow("(when (> 5 3) 'yes)"), "yes")
        XCTAssertEqual(try evalShow("(when (< 5 3) 'yes)"), "#f")
        XCTAssertEqual(try evalShow("(unless (< 5 3) 'ok)"), "ok")
    }

    func testUserSwapMacro() throws {
        let program = """
        (define-syntax swap!
          (syntax-rules ()
            ((_ a b) (let ((tmp a)) (set! a b) (set! b tmp)))))
        (define x 1)
        (define y 2)
        (swap! x y)
        (list x y)
        """
        XCTAssertEqual(try evalShow(program), "(2 1)")
    }

    func testSwapMacroHygiene() throws {
        let program = """
        (define-syntax swap!
          (syntax-rules ()
            ((_ a b) (let ((tmp a)) (set! a b) (set! b tmp)))))
        (define tmp 10)
        (define other 20)
        (swap! tmp other)
        (list tmp other)
        """
        XCTAssertEqual(try evalShow(program), "(20 10)")
    }

    func testEllipsisMacro() throws {
        let program = """
        (define-syntax my-list
          (syntax-rules ()
            ((_ e ...) (list e ...))))
        (my-list 1 2 3 4 5)
        """
        XCTAssertEqual(try evalShow(program), "(1 2 3 4 5)")
    }

    func testRecursiveMacro() throws {
        let program = """
        (define-syntax my-or
          (syntax-rules ()
            ((_) #f)
            ((_ e) e)
            ((_ e rest ...) (let ((t e)) (if t t (my-or rest ...))))))
        (list (my-or #f #f 7) (my-or) (my-or 3))
        """
        XCTAssertEqual(try evalShow(program), "(7 #f 3)")
    }

    func testMacroWithLiterals() throws {
        let program = """
        (define-syntax classify
          (syntax-rules (zero)
            ((_ zero) 'was-zero)
            ((_ x) 'was-other)))
        (list (classify zero) (classify 5))
        """
        XCTAssertEqual(try evalShow(program), "(was-zero was-other)")
    }

    func testNestedEllipsisTemplate() throws {
        let program = """
        (define-syntax my-let
          (syntax-rules ()
            ((_ ((name val) ...) body ...)
             ((lambda (name ...) body ...) val ...))))
        (my-let ((a 1) (b 2) (c 3)) (+ a b c))
        """
        XCTAssertEqual(try evalShow(program), "6")
    }
}
