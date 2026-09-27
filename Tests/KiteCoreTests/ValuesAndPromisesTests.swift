import XCTest
@testable import KiteCore

final class ValuesAndPromisesTests: XCTestCase {
    private func evalShow(_ src: String) throws -> String {
        writeString(try Interpreter().evalString(src))
    }

    func testCallWithValues() throws {
        XCTAssertEqual(try evalShow("(call-with-values (lambda () (values 1 2 3)) list)"), "(1 2 3)")
        XCTAssertEqual(try evalShow("(call-with-values (lambda () (values)) list)"), "()")
        XCTAssertEqual(try evalShow("(call-with-values (lambda () 5) (lambda (x) (* x x)))"), "25")
        XCTAssertEqual(try evalShow("(+ 1 (values 41))"), "42")
    }

    func testReceive() throws {
        XCTAssertEqual(try evalShow("(receive (q r) (exact-integer-sqrt 30) (list q r))"), "(5 5)")
        XCTAssertEqual(try evalShow("(receive (first . rest) (values 1 2 3) (list first rest))"), "(1 (2 3))")
        XCTAssertEqual(try evalShow("(receive all (values 'a 'b) all)"), "(a b)")
    }

    func testContinuationAcceptsMultipleValues() throws {
        XCTAssertEqual(try evalShow("(call-with-values (lambda () (call/cc (lambda (k) (k 1 2)))) list)"), "(1 2)")
    }

    func testDelayIsMemoized() throws {
        let program = """
        (define count 0)
        (define p (delay (begin (set! count (+ count 1)) (* 6 7))))
        (list (promise? p) (force p) (force p) count)
        """
        XCTAssertEqual(try evalShow(program), "(#t 42 42 1)")
    }

    func testMakePromiseAndForceOfNonPromise() throws {
        XCTAssertEqual(try evalShow("(force (make-promise 'ready))"), "ready")
        XCTAssertEqual(try evalShow("(let ((p (delay 1))) (eq? p (make-promise p)))"), "#t")
        XCTAssertEqual(try evalShow("(force 7)"), "7")
        XCTAssertEqual(try evalShow("(promise? (force (delay (delay 1))))"), "#t")
    }

    func testDelayForceRunsInConstantSpace() throws {
        let program = """
        (define (countdown n)
          (delay-force (if (= n 0) (delay 'bottom) (countdown (- n 1)))))
        (force (countdown 100000))
        """
        XCTAssertEqual(try evalShow(program), "bottom")
    }

    func testReentrantPromiseKeepsFirstValue() throws {
        let program = """
        (define x 5)
        (define p (delay (begin (set! x (+ x 1)) (if (> x 6) x (force p)))))
        (list (force p) (begin (set! x 100) (force p)))
        """
        XCTAssertEqual(try evalShow(program), "(7 7)")
    }

    func testLazyStream() throws {
        let program = """
        (define (integers-from n) (cons n (delay (integers-from (+ n 1)))))
        (define (stream-take s k)
          (if (= k 0) '() (cons (car s) (stream-take (force (cdr s)) (- k 1)))))
        (stream-take (integers-from 10) 5)
        """
        XCTAssertEqual(try evalShow(program), "(10 11 12 13 14)")
    }
}
