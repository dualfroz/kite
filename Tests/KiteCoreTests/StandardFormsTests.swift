import XCTest
@testable import KiteCore

final class StandardFormsTests: XCTestCase {
    private func evalShow(_ src: String) throws -> String {
        writeString(try Interpreter().evalString(src))
    }

    func testCaseLambdaDispatchesOnArgumentCount() throws {
        let program = """
        (define area
          (case-lambda
            ((r) (* 3 r r))
            ((w h) (* w h))
            ((a b . rest) (list 'many a b rest))))
        (list (area 2) (area 3 4) (area 1 2 3 4))
        """
        XCTAssertEqual(try evalShow(program), "(12 12 (many 1 2 (3 4)))")
        XCTAssertEqual(try evalShow("((case-lambda (() 'none) (args (length args))) 1 2 3)"), "3")
        XCTAssertThrowsError(try evalShow("((case-lambda ((a) a)) 1 2)"))
    }

    func testCaseLambdaTailCalls() throws {
        let program = """
        (define count
          (case-lambda
            ((n) (count n 0))
            ((n acc) (if (= n 0) acc (count (- n 1) (+ acc 1))))))
        (count 20000)
        """
        XCTAssertEqual(try evalShow(program), "20000")
    }

    func testLetValues() throws {
        let program = """
        (let-values (((a b) (values 1 2))
                     ((c . d) (values 3 4 5))
                     (all (values 6 7)))
          (list a b c d all))
        """
        XCTAssertEqual(try evalShow(program), "(1 2 3 (4 5) (6 7))")
        XCTAssertEqual(try evalShow("(let ((a 'outer)) (let-values (((a) (values 1)) ((b) (values a))) (list a b)))"), "(1 outer)")
        XCTAssertEqual(try evalShow("(let-values () 'empty)"), "empty")
    }

    func testLetStarValues() throws {
        XCTAssertEqual(try evalShow("(let*-values (((a b) (values 1 2)) ((c) (values (+ a b)))) (list a b c))"), "(1 2 3)")
        XCTAssertEqual(try evalShow("(let*-values (((q r) (floor/ -7 2))) (list q r))"), "(-4 1)")
    }

    func testDefineValues() throws {
        XCTAssertEqual(try evalShow("(define-values (q r . more) (values 1 2 3 4)) (list q r more)"), "(1 2 (3 4))")
        XCTAssertEqual(try evalShow("(define (f) (define-values (x y) (truncate/ -7 2)) (list x y)) (f)"), "(-3 -1)")
        XCTAssertEqual(try evalShow("(define-values all (values 'a 'b)) all"), "(a b)")
    }

    func testParameterize() throws {
        let program = """
        (define width (make-parameter 10))
        (define (show) (width))
        (list (show) (parameterize ((width 20)) (show)) (show))
        """
        XCTAssertEqual(try evalShow(program), "(10 20 10)")
    }

    func testParameterConverter() throws {
        let program = """
        (define radix (make-parameter "10" string->number))
        (list (radix) (parameterize ((radix "16")) (radix)) (radix))
        """
        XCTAssertEqual(try evalShow(program), "(10 16 10)")
    }

    func testParameterizeRestoresOnEscapeAndRaise() throws {
        let program = """
        (define level (make-parameter 'base))
        (define escaped (call/cc (lambda (k) (parameterize ((level 'inner)) (k (level))))))
        (define caught (guard (e (#t (list e (level)))) (parameterize ((level 'inner)) (raise (level)))))
        (list escaped (level) caught)
        """
        XCTAssertEqual(try evalShow(program), "(inner base (inner base))")
    }

    func testParameterizeReappliesOnReentry() throws {
        let program = """
        (define level (make-parameter 0))
        (let ((k #f) (seen '()))
          (parameterize ((level 1))
            (call/cc (lambda (c) (set! k c)))
            (set! seen (cons (level) seen)))
          (set! seen (cons (level) seen))
          (if (< (length seen) 4) (k #f) (reverse seen)))
        """
        XCTAssertEqual(try evalShow(program), "(1 0 1 0)")
    }

    func testDefineRecordType() throws {
        let program = """
        (define-record-type <point>
          (make-point x y)
          point?
          (x point-x set-point-x!)
          (y point-y))
        (define p (make-point 1 2))
        (set-point-x! p 10)
        (list p (point? p) (point? (vector 10 2)) (point-x p) (point-y p) <point>)
        """
        XCTAssertEqual(try evalShow(program), "(#<point x=10 y=2> #t #f 10 2 #<record-type point>)")
    }

    func testRecordConstructorSubsetAndTypeChecks() throws {
        let program = """
        (define-record-type node (make-node value) node? (value node-value) (next node-next set-node-next!))
        (define-record-type other (make-other) other?)
        (define n (make-node 5))
        (list (node-value n) (node? (make-other)) (equal? (make-node 1) (make-node 1)) (eq? n n))
        """
        XCTAssertEqual(try evalShow(program), "(5 #f #f #t)")
        XCTAssertThrowsError(try evalShow("(define-record-type a (make-a x) a? (x a-x)) (define-record-type b (make-b x) b? (x b-x)) (a-x (make-b 1))"))
        XCTAssertThrowsError(try evalShow("(define-record-type a (make-a x) a? (x a-x)) (make-a)"))
    }

    func testPreludeHelpersAreNotVisible() throws {
        for name in ["%apply", "%map", "%force", "%promise-done?", "%case-lambda", "%parameterize", "%accepts?"] {
            XCTAssertThrowsError(try evalShow(name), name)
        }
        XCTAssertEqual(try evalShow("(define (%map . args) 'mine) (map car '((1) (2)))"), "(1 2)")
    }

    func testUncaughtErrorRunsPendingAfterThunks() {
        let interp = Interpreter()
        var captured = ""
        interp.output = { captured += $0 }
        let program = """
        (dynamic-wind
          (lambda () (display "outer-in "))
          (lambda ()
            (dynamic-wind
              (lambda () (display "inner-in "))
              (lambda () (car '()))
              (lambda () (display "inner-out "))))
          (lambda () (display "outer-out")))
        """
        XCTAssertThrowsError(try interp.evalString(program)) { error in
            XCTAssertEqual((error as? SchemeError)?.message, "car: expected pair")
        }
        XCTAssertEqual(captured, "outer-in inner-in inner-out outer-out")
    }
}
