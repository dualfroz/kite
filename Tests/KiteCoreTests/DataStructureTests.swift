import XCTest
@testable import KiteCore

final class DataStructureTests: XCTestCase {
    private func evalShow(_ src: String) throws -> String {
        writeString(try Interpreter().evalString(src))
    }

    func testVectorLiteralsAreSelfEvaluating() throws {
        XCTAssertEqual(try evalShow("#(1 \"two\" (3))"), "#(1 \"two\" (3))")
        XCTAssertEqual(try evalShow("(vector? #(1 2))"), "#t")
        XCTAssertEqual(try evalShow("(vector? '(1 2))"), "#f")
    }

    func testVectorOperations() throws {
        let program = """
        (define v (make-vector 3 0))
        (vector-set! v 0 'a)
        (vector-fill! v 'z 1)
        (list v (vector-length v) (vector-ref v 0)
              (vector->list #(1 2 3 4) 1 3)
              (list->vector '(x y))
              (vector-copy #(1 2 3) 1)
              (vector-append #(1) #(2 3)))
        """
        XCTAssertEqual(try evalShow(program), "(#(a z z) 3 a (2 3) #(x y) #(2 3) #(1 2 3))")
    }

    func testVectorHigherOrder() throws {
        XCTAssertEqual(try evalShow("(vector-map + #(1 2 3) #(10 20 30))"), "#(11 22 33)")
        let program = """
        (define total 0)
        (vector-for-each (lambda (x) (set! total (+ total x))) #(1 2 3 4))
        total
        """
        XCTAssertEqual(try evalShow(program), "10")
    }

    func testVectorEqualityAndQuasiquote() throws {
        XCTAssertEqual(try evalShow("(list (equal? #(1 (2)) #(1 (2))) (eqv? #(1) #(1)))"), "(#t #f)")
        XCTAssertEqual(try evalShow("(let ((x 2)) `#(1 ,x ,@(list 3 4)))"), "#(1 2 3 4)")
    }

    func testVectorIndexErrors() {
        XCTAssertThrowsError(try evalShow("(vector-ref #(1 2) 2)"))
        XCTAssertThrowsError(try evalShow("(vector-ref #(1 2) -1)"))
    }

    func testHashTableBasics() throws {
        let program = """
        (define t (make-hash-table))
        (hash-table-set! t 'a 1)
        (hash-table-set! t "key" 2)
        (hash-table-set! t '(1 2) 3)
        (hash-table-set! t 'a 10)
        (list (hash-table-ref t 'a)
              (hash-table-ref t "key")
              (hash-table-ref t (list 1 2))
              (hash-table-ref/default t 'missing 'none)
              (hash-table-ref t 'missing (lambda () 'thunk))
              (hash-table-count t)
              (hash-table-keys t)
              (hash-table-values t))
        """
        XCTAssertEqual(try evalShow(program), "(10 2 3 none thunk 3 (a \"key\" (1 2)) (10 2 3))")
    }

    func testHashTableMissingKeyRaises() throws {
        XCTAssertThrowsError(try evalShow("(hash-table-ref (make-hash-table) 'x)"))
        let program = """
        (guard (e ((error-object? e) (error-object-irritants e)))
          (hash-table-ref (make-hash-table) 'x))
        """
        XCTAssertEqual(try evalShow(program), "(x)")
    }

    func testHashTableUpdateDeleteAndWalk() throws {
        let program = """
        (define t (alist->hash-table '((a . 1) (b . 2) (a . 99))))
        (hash-table-update! t 'a (lambda (v) (* v 100)))
        (hash-table-update! t 'c (lambda (v) (+ v 1)) (lambda () 0))
        (hash-table-update!/default t 'd (lambda (v) (cons 'x v)) '())
        (hash-table-delete! t 'b)
        (define seen '())
        (hash-table-walk t (lambda (k v) (set! seen (cons (list k v) seen))))
        (list (hash-table->alist t)
              (reverse seen)
              (hash-table-contains? t 'b)
              (hash-table-exists? t 'c))
        """
        XCTAssertEqual(try evalShow(program), "(((a . 100) (c . 1) (d x)) ((a 100) (c 1) (d (x))) #f #t)")
    }

    func testHashTableEquivalenceKinds() throws {
        let program = """
        (define by-identity (make-hash-table eq?))
        (define by-value (make-hash-table equal?))
        (define key (list 1 2))
        (hash-table-set! by-identity key 'found)
        (hash-table-set! by-value key 'found)
        (set-car! key 7)
        (list (hash-table-ref/default by-identity key 'lost)
              (hash-table-ref/default by-identity (list 7 2) 'lost)
              (hash-table-ref/default by-value (list 1 2) 'lost))
        """
        XCTAssertEqual(try evalShow(program), "(found lost lost)")
    }

    func testHashTableCopyAndClear() throws {
        let program = """
        (define t (make-hash-table))
        (hash-table-set! t 1 'one)
        (define c (hash-table-copy t))
        (hash-table-clear! t)
        (list (hash-table-count t) (hash-table-ref/default c 1 #f) (hash-table? c))
        """
        XCTAssertEqual(try evalShow(program), "(0 one #t)")
    }

    func testManyHashTableEntries() throws {
        let program = """
        (define t (make-hash-table))
        (do ((i 0 (+ i 1))) ((= i 2000)) (hash-table-set! t i (* i i)))
        (do ((i 0 (+ i 2))) ((>= i 2000)) (hash-table-delete! t i))
        (list (hash-table-count t) (hash-table-ref t 1999) (hash-table-ref/default t 1000 'gone))
        """
        XCTAssertEqual(try evalShow(program), "(1000 3996001 gone)")
    }
}
