import XCTest
@testable import KiteCore

final class TailCallTests: XCTestCase {
    private func evalShow(_ src: String) throws -> String {
        displayString(try Interpreter().evalString(src))
    }

    private func frameCount(_ kont: Kont) -> Int {
        var count = 0
        var current = kont
        while true {
            switch current {
            case .done:
                return count
            case .ifK(_, _, _, let next), .defineK(_, _, let next), .setK(_, _, let next),
                 .argsK(_, _, _, let next), .seqK(_, _, let next), .popHandlerK(let next),
                 .afterHandlerK(_, _, let next), .dwBeforeK(_, _, _, let next), .dwThunkK(_, _, let next),
                 .dwAfterK(_, let next), .callValuesK(_, let next):
                current = next
            case .rewindK(_, _, _, _, let saved):
                current = saved
            }
            count += 1
        }
    }

    private func framesAtBottom(_ src: String) throws -> Int {
        guard case .continuation(let kont, _, _) = try Interpreter().evalString(src) else {
            XCTFail("program did not return a continuation")
            return -1
        }
        return frameCount(kont)
    }

    func testTailLoopKeepsContinuationFlat() throws {
        let shallow = try framesAtBottom("""
        (define (loop i) (if (= i 10) (call/cc (lambda (k) k)) (loop (+ i 1))))
        (loop 0)
        """)
        let deep = try framesAtBottom("""
        (define (loop i) (if (= i 50000) (call/cc (lambda (k) k)) (loop (+ i 1))))
        (loop 0)
        """)
        XCTAssertEqual(shallow, deep)
        XCTAssertLessThan(deep, 5)
    }

    func testNonTailRecursionGrowsContinuation() throws {
        let frames = try framesAtBottom("""
        (define result #f)
        (define (dig i) (if (= i 2000) (call/cc (lambda (k) (set! result k) 0)) (+ 1 (dig (+ i 1)))))
        (dig 0)
        result
        """)
        XCTAssertGreaterThan(frames, 1000)
    }

    func testTailCallsThroughDerivedFormsStayFlat() throws {
        let forms = [
            "(cond ((= i 20000) (call/cc (lambda (k) k))) (else (loop (+ i 1))))",
            "(case (if (= i 20000) 'stop 'go) ((stop) (call/cc (lambda (k) k))) (else (loop (+ i 1))))",
            "(or (and (= i 20000) (call/cc (lambda (k) k))) (loop (+ i 1)))",
            "(when #t (if (= i 20000) (call/cc (lambda (k) k)) (loop (+ i 1))))",
            "(let ((j (+ i 1))) (if (= i 20000) (call/cc (lambda (k) k)) (loop j)))",
            "(apply (if (= i 20000) (lambda () (call/cc (lambda (k) k))) (lambda () (loop (+ i 1)))) '())",
        ]
        for body in forms {
            let frames = try framesAtBottom("(define (loop i) \(body)) (loop 0)")
            XCTAssertLessThan(frames, 5, body)
        }
    }

    func testDeepNamedLetLoop() throws {
        let program = """
        (define (count-up n)
          (let loop ((i 0))
            (if (= i n) i (loop (+ i 1)))))
        (count-up 100000)
        """
        XCTAssertEqual(try evalShow(program), "100000")
    }

    func testMutualTailRecursion() throws {
        let program = """
        (define (even? n) (if (= n 0) #t (odd? (- n 1))))
        (define (odd? n) (if (= n 0) #f (even? (- n 1))))
        (even? 100000)
        """
        XCTAssertEqual(try evalShow(program), "#t")
    }

    func testDoLoopStaysFlat() throws {
        let frames = try framesAtBottom("(do ((i 0 (+ i 1))) ((= i 20000) (call/cc (lambda (k) k))))")
        XCTAssertLessThan(frames, 5)
    }
}
