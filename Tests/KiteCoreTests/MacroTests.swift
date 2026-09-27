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

    func testFreeIdentifierIgnoresLocalShadowing() throws {
        let program = """
        (define-syntax my-list
          (syntax-rules ()
            ((_ e ...) (list e ...))))
        (let ((list (lambda args 'shadowed)))
          (my-list 1 2))
        """
        XCTAssertEqual(try evalShow(program), "(1 2)")
    }

    func testFreeIdentifierRefersToDefinitionScope() throws {
        let program = """
        (let ((x 'outer))
          (let-syntax ((get-x (syntax-rules () ((_) x))))
            (let ((x 'inner))
              (get-x))))
        """
        XCTAssertEqual(try evalShow(program), "outer")
    }

    func testMacroCanSetFreeVariableOfDefinitionScope() throws {
        let program = """
        (define counter 0)
        (define-syntax bump! (syntax-rules () ((_) (set! counter (+ counter 1)))))
        (let ((counter 100))
          (bump!)
          (bump!))
        counter
        """
        XCTAssertEqual(try evalShow(program), "2")
    }

    func testKeywordsInTemplatesSurviveShadowing() throws {
        let program = """
        (define-syntax swap!
          (syntax-rules ()
            ((_ a b) (let ((tmp a)) (set! a b) (set! b tmp)))))
        (let ((let 'not-a-keyword) (if 'nope) (x 1) (y 2))
          (swap! x y)
          (list x y))
        """
        XCTAssertEqual(try evalShow(program), "(2 1)")
    }

    func testDerivedFormsIgnoreShadowedPrimitives() throws {
        XCTAssertEqual(try evalShow("(let ((cons list) (append 0)) `(1 ,@(list 2 3) ,(+ 2 2)))"), "(1 2 3 4)")
        XCTAssertEqual(try evalShow("(let ((memv #f)) (case 3 ((1 2) 'low) ((3) 'three) (else 'high)))"), "three")
    }

    func testQuotedSymbolsInTemplatesStayPlain() throws {
        let program = """
        (define-syntax tag
          (syntax-rules ()
            ((_ x) `(tagged ,x ,(list 'inner x)))))
        (let ((result (tag 5)))
          (list result (eq? (car result) 'tagged) (eq? (car (caddr result)) 'inner)))
        """
        XCTAssertEqual(try evalShow(program), "((tagged 5 (inner 5)) #t #t)")
    }

    func testLetrecSyntaxRecursion() throws {
        let program = """
        (letrec-syntax ((my-and (syntax-rules ()
                                  ((_) #t)
                                  ((_ e) e)
                                  ((_ e rest ...) (if e (my-and rest ...) #f)))))
          (list (my-and 1 2 3) (my-and 1 #f 3)))
        """
        XCTAssertEqual(try evalShow(program), "(3 #f)")
    }

    func testDoLoop() throws {
        XCTAssertEqual(try evalShow("(do ((i 0 (+ i 1)) (acc '() (cons i acc))) ((= i 4) acc))"), "(3 2 1 0)")
        XCTAssertEqual(try evalShow("(let ((v (make-vector 3))) (do ((i 0 (+ i 1))) ((= i 3) v) (vector-set! v i (* i i))))"), "#(0 1 4)")
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
