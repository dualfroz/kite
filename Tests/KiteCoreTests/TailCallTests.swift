import XCTest
@testable import KiteCore

final class TailCallTests: XCTestCase {
    private func evalShow(_ src: String) throws -> String {
        displayString(try Interpreter().evalString(src))
    }

    func testDeepNamedLetLoop() throws {
        let program = """
        (define (count-up n)
          (let loop ((i 0))
            (if (= i n) i (loop (+ i 1)))))
        (count-up 1000000)
        """
        XCTAssertEqual(try evalShow(program), "1000000")
    }

    func testDeepTailRecursiveAccumulator() throws {
        let program = """
        (define (sum-to n acc)
          (if (= n 0) acc (sum-to (- n 1) (+ acc 1))))
        (sum-to 1000000 0)
        """
        XCTAssertEqual(try evalShow(program), "1000000")
    }

    func testMutualTailRecursion() throws {
        let program = """
        (define (even? n) (if (= n 0) #t (odd? (- n 1))))
        (define (odd? n) (if (= n 0) #f (even? (- n 1))))
        (even? 500000)
        """
        XCTAssertEqual(try evalShow(program), "#t")
    }

    func testTailPositionInCond() throws {
        let program = """
        (define (loop i n)
          (cond ((= i n) 'done)
                (else (loop (+ i 1) n))))
        (loop 0 500000)
        """
        XCTAssertEqual(try evalShow(program), "done")
    }
}
