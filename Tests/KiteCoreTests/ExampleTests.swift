import XCTest
@testable import KiteCore

final class ExampleTests: XCTestCase {
    private func examplesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("examples")
    }

    private func runExample(_ name: String) throws -> String {
        let url = examplesDirectory().appendingPathComponent(name)
        let source = try String(contentsOf: url, encoding: .utf8)
        let interp = Interpreter()
        var captured = ""
        interp.output = { captured += $0 }
        try interp.evalString(source)
        return captured
    }

    func testFibExample() throws {
        XCTAssertEqual(try runExample("fib.scm"), "fib 10 = 55\nfib 20 = 6765\nfib 25 = 75025\n")
    }

    func testFactorialExample() throws {
        XCTAssertEqual(try runExample("factorial.scm"), "10! = 3628800\n20! = 2432902008176640000\n")
    }

    func testMapsExample() throws {
        let expected = """
        squares: (1 4 9 16 25)
        odds: (1 3 5 7)
        sum via fold: 55
        zip-add: (11 22 33)
        for-each: abcd
        append+reverse: (6 5 4 3 2 1)

        """
        XCTAssertEqual(try runExample("maps.scm"), expected)
    }

    func testCallCCExample() throws {
        let expected = """
        product 1..5 = 120
        product with a zero = 0
        reentry sum 1..5 = 15

        """
        XCTAssertEqual(try runExample("callcc.scm"), expected)
    }

    func testMacrosExample() throws {
        let expected = """
        swap x y -> (2 1)
        swap tmp other -> (20 10)
        my-list -> (1 2 3 4 5)
        my-or -> 7
        when fired
        unless fired

        """
        XCTAssertEqual(try runExample("macros.scm"), expected)
    }

    func testTailLoopExample() throws {
        XCTAssertEqual(try runExample("tailloop.scm"), "counted to 100000\neven? 100000 -> #t\n")
    }

    func testExceptionsExample() throws {
        let expected = """
        10 / 4 = 5/2
        error: division by zero
        42 -> 42
        abc -> rejected: not a number
        -3 -> rejected: negative
        dynamic-wind trail: (open work close (caught disk-full))
        continuable: 3

        """
        XCTAssertEqual(try runExample("exceptions.scm"), expected)
    }

    func testStreamsExample() throws {
        let expected = """
        primes: (2 3 5 7 11 13 17 19 23 29)
        fib 100 = 354224848179261915075
        forced twice, evaluated 1 time
        delay-force chain of 100000: liftoff

        """
        XCTAssertEqual(try runExample("streams.scm"), expected)
    }

    func testWordCountExample() throws {
        let expected = """
        distinct words: 11
        top three: the=4 dog=2 fox=2 \("")
        words by length: #(0 0 0 9 3 3 1 0)

        """
        XCTAssertEqual(try runExample("wordcount.scm"), expected)
    }
}
