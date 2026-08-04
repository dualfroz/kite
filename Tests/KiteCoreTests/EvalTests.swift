import XCTest
@testable import KiteCore

final class EvalTests: XCTestCase {
    private func eval(_ src: String) throws -> Value {
        try Interpreter().evalString(src)
    }

    private func evalShow(_ src: String) throws -> String {
        displayString(try eval(src))
    }

    func testArithmetic() throws {
        XCTAssertEqual(try evalShow("(+ 1 2 3 4)"), "10")
        XCTAssertEqual(try evalShow("(- 10 3 2)"), "5")
        XCTAssertEqual(try evalShow("(* 2 3 4)"), "24")
        XCTAssertEqual(try evalShow("(- 5)"), "-5")
        XCTAssertEqual(try evalShow("(+ )"), "0")
    }

    func testRationalArithmetic() throws {
        XCTAssertEqual(try evalShow("(/ 3 2)"), "3/2")
        XCTAssertEqual(try evalShow("(/ 6 2)"), "3")
        XCTAssertEqual(try evalShow("(+ 1/2 1/3)"), "5/6")
        XCTAssertEqual(try evalShow("(* 2/3 3/4)"), "1/2")
    }

    func testRealArithmetic() throws {
        XCTAssertEqual(try evalShow("(+ 1.5 2.5)"), "4.0")
        XCTAssertEqual(try evalShow("(* 2 1.5)"), "3.0")
    }

    func testComparisons() throws {
        XCTAssertEqual(try evalShow("(< 1 2 3)"), "#t")
        XCTAssertEqual(try evalShow("(< 1 3 2)"), "#f")
        XCTAssertEqual(try evalShow("(= 2 2 2)"), "#t")
        XCTAssertEqual(try evalShow("(>= 3 3 2)"), "#t")
    }

    func testIntegerOps() throws {
        XCTAssertEqual(try evalShow("(modulo 7 3)"), "1")
        XCTAssertEqual(try evalShow("(modulo -7 3)"), "2")
        XCTAssertEqual(try evalShow("(remainder -7 3)"), "-1")
        XCTAssertEqual(try evalShow("(quotient 17 5)"), "3")
        XCTAssertEqual(try evalShow("(expt 2 10)"), "1024")
        XCTAssertEqual(try evalShow("(gcd 12 18)"), "6")
    }

    func testDefineAndLambda() throws {
        XCTAssertEqual(try evalShow("(define (square x) (* x x)) (square 9)"), "81")
        XCTAssertEqual(try evalShow("((lambda (a b) (+ a b)) 3 4)"), "7")
        XCTAssertEqual(try evalShow("((lambda args (length args)) 1 2 3)"), "3")
        XCTAssertEqual(try evalShow("((lambda (a . rest) rest) 1 2 3)"), "(2 3)")
    }

    func testClosuresAndSet() throws {
        let counter = """
        (define (make-counter)
          (let ((n 0))
            (lambda () (set! n (+ n 1)) n)))
        (define c (make-counter))
        (c) (c)
        (c)
        """
        XCTAssertEqual(try evalShow(counter), "3")
    }

    func testLetForms() throws {
        XCTAssertEqual(try evalShow("(let ((a 1) (b 2)) (+ a b))"), "3")
        XCTAssertEqual(try evalShow("(let* ((a 1) (b (+ a 1))) (* a b))"), "2")
        XCTAssertEqual(try evalShow("(letrec ((e? (lambda (n) (if (= n 0) #t (o? (- n 1))))) (o? (lambda (n) (if (= n 0) #f (e? (- n 1)))))) (e? 10))"), "#t")
    }

    func testCondCaseAndOr() throws {
        XCTAssertEqual(try evalShow("(cond ((= 1 2) 'a) ((= 1 1) 'b) (else 'c))"), "b")
        XCTAssertEqual(try evalShow("(cond ((assv 2 '((1 . a) (2 . b))) => cdr) (else 'none))"), "b")
        XCTAssertEqual(try evalShow("(case 3 ((1 2) 'low) ((3 4) 'mid) (else 'high))"), "mid")
        XCTAssertEqual(try evalShow("(and 1 2 3)"), "3")
        XCTAssertEqual(try evalShow("(and 1 #f 3)"), "#f")
        XCTAssertEqual(try evalShow("(or #f #f 7)"), "7")
        XCTAssertEqual(try evalShow("(or #f #f)"), "#f")
    }

    func testListOps() throws {
        XCTAssertEqual(try evalShow("(car '(1 2 3))"), "1")
        XCTAssertEqual(try evalShow("(cdr '(1 2 3))"), "(2 3)")
        XCTAssertEqual(try evalShow("(cons 1 '(2 3))"), "(1 2 3)")
        XCTAssertEqual(try evalShow("(append '(1 2) '(3 4) '(5))"), "(1 2 3 4 5)")
        XCTAssertEqual(try evalShow("(reverse '(1 2 3))"), "(3 2 1)")
        XCTAssertEqual(try evalShow("(length '(a b c d))"), "4")
        XCTAssertEqual(try evalShow("(list-ref '(a b c) 1)"), "b")
        XCTAssertEqual(try evalShow("(map (lambda (x) (* x x)) '(1 2 3))"), "(1 4 9)")
        XCTAssertEqual(try evalShow("(filter even? '(1 2 3 4 5 6))"), "(2 4 6)")
        XCTAssertEqual(try evalShow("(assq 'b '((a . 1) (b . 2)))"), "(b . 2)")
        XCTAssertEqual(try evalShow("(member 3 '(1 2 3 4))"), "(3 4)")
    }

    func testPredicates() throws {
        XCTAssertEqual(try evalShow("(null? '())"), "#t")
        XCTAssertEqual(try evalShow("(pair? '(1))"), "#t")
        XCTAssertEqual(try evalShow("(pair? '())"), "#f")
        XCTAssertEqual(try evalShow("(eq? 'a 'a)"), "#t")
        XCTAssertEqual(try evalShow("(equal? '(1 2 (3)) '(1 2 (3)))"), "#t")
        XCTAssertEqual(try evalShow("(eqv? 2 2)"), "#t")
        XCTAssertEqual(try evalShow("(number? 5)"), "#t")
        XCTAssertEqual(try evalShow("(procedure? car)"), "#t")
    }

    func testQuasiquote() throws {
        XCTAssertEqual(try evalShow("(let ((x 5)) `(a ,x c))"), "(a 5 c)")
        XCTAssertEqual(try evalShow("(let ((xs '(2 3))) `(1 ,@xs 4))"), "(1 2 3 4)")
    }

    func testApply() throws {
        XCTAssertEqual(try evalShow("(apply + '(1 2 3 4))"), "10")
        XCTAssertEqual(try evalShow("(apply + 1 2 '(3 4))"), "10")
        XCTAssertEqual(try evalShow("(apply max '(3 1 4 1 5 9 2 6))"), "9")
    }

    func testStrings() throws {
        XCTAssertEqual(try evalShow("(string-append \"foo\" \"bar\")"), "foobar")
        XCTAssertEqual(try evalShow("(string-length \"hello\")"), "5")
        XCTAssertEqual(try evalShow("(substring \"hello\" 1 4)"), "ell")
        XCTAssertEqual(try evalShow("(number->string 42)"), "42")
        XCTAssertEqual(try evalShow("(string->number \"3/4\")"), "3/4")
    }

    func testUnboundVariableThrows() throws {
        XCTAssertThrowsError(try eval("(+ 1 undefined-thing)"))
    }

    func testCapturedOutput() throws {
        let interp = Interpreter()
        var captured = ""
        interp.output = { captured += $0 }
        try interp.evalString("(display \"result: \") (display (+ 40 2)) (newline)")
        XCTAssertEqual(captured, "result: 42\n")
    }
}
