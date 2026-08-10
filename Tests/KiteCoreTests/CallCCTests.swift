import XCTest
@testable import KiteCore

final class CallCCTests: XCTestCase {
    private func evalShow(_ src: String) throws -> String {
        displayString(try Interpreter().evalString(src))
    }

    func testEarlyExit() throws {
        let program = """
        (define (product items)
          (call/cc
            (lambda (break)
              (let loop ((xs items) (acc 1))
                (cond ((null? xs) acc)
                      ((= (car xs) 0) (break 0))
                      (else (loop (cdr xs) (* acc (car xs)))))))))
        (list (product '(1 2 3 4)) (product '(1 2 0 4)))
        """
        XCTAssertEqual(try evalShow(program), "(24 0)")
    }

    func testContinuationValueWhenNotInvoked() throws {
        XCTAssertEqual(try evalShow("(+ 1 (call/cc (lambda (k) 10)))"), "11")
    }

    func testReentrantContinuationLoop() throws {
        let program = """
        (let ((sum 0) (i 0) (k #f))
          (call/cc (lambda (c) (set! k c)))
          (set! i (+ i 1))
          (set! sum (+ sum i))
          (if (< i 5) (k #f) sum))
        """
        XCTAssertEqual(try evalShow(program), "15")
    }

    func testMultiShotContinuationAccumulates() throws {
        let program = """
        (let ((results '()) (k #f) (n 0))
          (set! n (+ 1 (call/cc (lambda (c) (set! k c) 0))))
          (set! results (cons n results))
          (if (< n 4) (k n) results))
        """
        XCTAssertEqual(try evalShow(program), "(4 3 2 1)")
    }
}
