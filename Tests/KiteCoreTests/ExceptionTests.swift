import XCTest
@testable import KiteCore

final class ExceptionTests: XCTestCase {
    private func evalShow(_ src: String) throws -> String {
        writeString(try Interpreter().evalString(src))
    }

    func testGuardCatchesErrorObjects() throws {
        let program = """
        (guard (e ((error-object? e) (list (error-object-message e) (error-object-irritants e))))
          (error "bad input" 1 'two))
        """
        XCTAssertEqual(try evalShow(program), "(\"bad input\" (1 two))")
    }

    func testGuardCatchesRaisedValues() throws {
        XCTAssertEqual(try evalShow("(guard (e ((symbol? e) (list 'symbol e))) (raise 'oops))"), "(symbol oops)")
        XCTAssertEqual(try evalShow("(guard (e ((assq 'code e) => cdr)) (raise '((code . 404))))"), "404")
        XCTAssertEqual(try evalShow("(guard (e (else 'fallback)) (raise 1))"), "fallback")
    }

    func testGuardCatchesPrimitiveErrors() throws {
        XCTAssertEqual(try evalShow("(guard (e ((error-object? e) (error-object-message e))) (car 5))"), "\"car: expected pair\"")
        XCTAssertEqual(try evalShow("(guard (e (#t 'caught)) (undefined-variable))"), "caught")
        XCTAssertEqual(try evalShow("(guard (e (#t 'caught)) (vector-ref (vector) 0))"), "caught")
    }

    func testGuardReturnsBodyValuesWhenNothingIsRaised() throws {
        XCTAssertEqual(try evalShow("(guard (e (#t 'caught)) (+ 1 2))"), "3")
        XCTAssertEqual(try evalShow("(call-with-values (lambda () (guard (e (#t #f)) (values 1 2))) list)"), "(1 2)")
    }

    func testUnmatchedGuardReraisesToOuterGuard() throws {
        let program = """
        (guard (outer ((string? outer) (list 'outer outer)))
          (guard (inner ((number? inner) 'inner))
            (raise "text")))
        """
        XCTAssertEqual(try evalShow(program), "(outer \"text\")")
    }

    func testUncaughtRaiseReachesSwift() {
        XCTAssertThrowsError(try evalShow("(raise 'nobody-home)")) { error in
            let schemeError = error as? SchemeError
            XCTAssertEqual(schemeError?.description, "uncaught exception: nobody-home")
            if case .symbol(let name)? = schemeError?.condition {
                XCTAssertEqual(name, "nobody-home")
            } else {
                XCTFail("condition not preserved")
            }
        }
        XCTAssertThrowsError(try evalShow("(guard (e ((string? e) 'no)) (error \"still failing\" 7))")) { error in
            XCTAssertEqual((error as? SchemeError)?.description, "still failing 7")
        }
    }

    func testRaiseContinuableResumes() throws {
        let program = """
        (with-exception-handler
          (lambda (condition) (* condition 10))
          (lambda () (+ 1 (raise-continuable 4))))
        """
        XCTAssertEqual(try evalShow(program), "41")
    }

    func testHandlerReturningFromRaiseIsAnError() {
        XCTAssertThrowsError(try evalShow("(with-exception-handler (lambda (c) 0) (lambda () (raise 'x)))"))
    }

    func testHandlerRunsInOuterHandlerContext() throws {
        let program = """
        (guard (e (#t (list 'outer e)))
          (with-exception-handler
            (lambda (c) (raise (list 'wrapped c)))
            (lambda () (raise 'inner))))
        """
        XCTAssertEqual(try evalShow(program), "(outer (wrapped inner))")
    }

    func testHandlerIsRemovedAfterThunkReturns() throws {
        let program = """
        (define log '())
        (guard (e (#t (cons e log)))
          (with-exception-handler
            (lambda (c) (set! log (cons c log)) 0)
            (lambda () (raise-continuable 'first)))
          (raise 'second))
        """
        XCTAssertEqual(try evalShow(program), "(second first)")
    }

    func testDynamicWindRunsAfterOnEscape() throws {
        let program = """
        (define trail '())
        (define (note x) (set! trail (cons x trail)))
        (define result
          (call/cc (lambda (escape)
            (dynamic-wind
              (lambda () (note 'before))
              (lambda () (escape 'escaped) (note 'unreachable))
              (lambda () (note 'after))))))
        (list result (reverse trail))
        """
        XCTAssertEqual(try evalShow(program), "(escaped (before after))")
    }

    func testDynamicWindRerunsBeforeOnReentry() throws {
        let program = """
        (define trail '())
        (define (note x) (set! trail (cons x trail)))
        (let ((k #f) (runs 0))
          (dynamic-wind
            (lambda () (note 'before))
            (lambda () (call/cc (lambda (c) (set! k c))) (note 'during))
            (lambda () (note 'after)))
          (if (< runs 2) (begin (set! runs (+ runs 1)) (k #f)))
          (reverse trail))
        """
        XCTAssertEqual(try evalShow(program), "(before during after before during after before during after)")
    }

    func testDynamicWindWithGuard() throws {
        let program = """
        (define trail '())
        (define (note x) (set! trail (cons x trail)))
        (define value
          (guard (e (#t (note 'handler) e))
            (dynamic-wind
              (lambda () (note 'in))
              (lambda () (raise 'boom))
              (lambda () (note 'out)))))
        (list value (reverse trail))
        """
        XCTAssertEqual(try evalShow(program), "(boom (in out handler))")
    }

    func testNestedDynamicWindUnwindsInnermostFirst() throws {
        let program = """
        (define trail '())
        (define (note x) (set! trail (cons x trail)))
        (call/cc (lambda (k)
          (dynamic-wind
            (lambda () (note 'outer-in))
            (lambda ()
              (dynamic-wind
                (lambda () (note 'inner-in))
                (lambda () (k 'done))
                (lambda () (note 'inner-out))))
            (lambda () (note 'outer-out)))))
        (reverse trail)
        """
        XCTAssertEqual(try evalShow(program), "(outer-in inner-in inner-out outer-out)")
    }

    func testErrorObjectPredicates() throws {
        XCTAssertEqual(try evalShow("(guard (e (#t (list (error-object? e) (read-error? e) (file-error? e)))) (error \"x\"))"), "(#t #f #f)")
        XCTAssertEqual(try evalShow("(guard (e (#t (read-error? e))) (read (open-input-string \"(1 2\")))"), "#t")
        XCTAssertEqual(try evalShow("(error-object? 'nope)"), "#f")
    }
}
