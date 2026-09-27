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

    func testEscapeFromHigherOrderProcedures() throws {
        let cases = [
            ("(map (lambda (x) (if (= x 2) (k 100) x)) '(1 2 3))", "101"),
            ("(for-each (lambda (x) (if (= x 2) (k 100))) '(1 2 3))", "101"),
            ("(filter (lambda (x) (if (= x 2) (k 100) #t)) '(1 2 3))", "101"),
            ("(fold-left (lambda (acc x) (if (= x 2) (k 100) x)) 0 '(1 2 3))", "101"),
            ("(fold-right (lambda (x acc) (if (= x 2) (k 100) x)) 0 '(1 2 3))", "101"),
            ("(vector-map (lambda (x) (if (= x 2) (k 100) x)) #(1 2 3))", "101"),
            ("(map (lambda (x y) (if (= y 20) (k 100) x)) '(1 2) '(10 20))", "101"),
        ]
        for (body, expected) in cases {
            XCTAssertEqual(try evalShow("(+ 1 (call/cc (lambda (k) \(body))))"), expected, body)
        }
    }

    func testReentryIntoMap() throws {
        let program = """
        (let ((k* #f) (n 0))
          (let ((r (map (lambda (x) (call/cc (lambda (k) (if (= x 2) (set! k* k)) x))) '(1 2 3))))
            (set! n (+ n 1))
            (if (< n 3) (k* (* n 10)) r)))
        """
        XCTAssertEqual(try evalShow(program), "(1 20 3)")
    }

    func testGeneratorViaReentry() throws {
        let program = """
        (define (make-generator items)
          (define return #f)
          (define (resume-point)
            (for-each (lambda (item) (call/cc (lambda (next) (set! resume-point (lambda () (next #f))) (return item)))) items)
            (return 'done))
          (lambda () (call/cc (lambda (r) (set! return r) (resume-point)))))
        (define gen (make-generator '(a b c)))
        (define first (gen))
        (define second (gen))
        (define third (gen))
        (list first second third (gen))
        """
        XCTAssertEqual(try evalShow(program), "(a b c done)")
    }
}
