import Foundation

let preludeSource = """
(define-syntax when
  (syntax-rules ()
    ((_ test body ...) (if test (begin body ...) #f))))

(define-syntax unless
  (syntax-rules ()
    ((_ test body ...) (if test #f (begin body ...)))))
"""

func installBuiltins(into env: Environment, interp: Interpreter) {
    func def(_ name: String, _ special: SpecialKind = .none, _ fn: @escaping ([Value]) throws -> Value) {
        env.define(name, .builtin(Builtin(name: name, special: special, fn: fn)))
    }

    def("+") { args in
        var acc = Num.int(0)
        for a in args { acc = numAdd(acc, try asNum(a, "+")) }
        return numToValue(acc)
    }
    def("*") { args in
        var acc = Num.int(1)
        for a in args { acc = numMul(acc, try asNum(a, "*")) }
        return numToValue(acc)
    }
    def("-") { args in
        guard let first = args.first else { throw schemeError("-: needs at least 1 argument") }
        if args.count == 1 {
            return numToValue(numSub(.int(0), try asNum(first, "-")))
        }
        var acc = try asNum(first, "-")
        for a in args[1...] { acc = numSub(acc, try asNum(a, "-")) }
        return numToValue(acc)
    }
    def("/") { args in
        guard let first = args.first else { throw schemeError("/: needs at least 1 argument") }
        if args.count == 1 {
            return numToValue(try numDiv(.int(1), try asNum(first, "/")))
        }
        var acc = try asNum(first, "/")
        for a in args[1...] { acc = try numDiv(acc, try asNum(a, "/")) }
        return numToValue(acc)
    }

    func chainCompare(_ name: String, _ pred: @escaping (Int) -> Bool) {
        def(name) { args in
            for i in 1..<max(args.count, 1) where i < args.count {
                let c = numCompare(try asNum(args[i - 1], name), try asNum(args[i], name))
                if !pred(c) { return .bool(false) }
            }
            return .bool(true)
        }
    }
    chainCompare("=") { $0 == 0 }
    chainCompare("<") { $0 < 0 }
    chainCompare(">") { $0 > 0 }
    chainCompare("<=") { $0 <= 0 }
    chainCompare(">=") { $0 >= 0 }

    func intArg(_ v: Value, _ who: String) throws -> Int {
        guard case .integer(let n) = v else { throw schemeError("\(who): expected integer", [v]) }
        return n
    }
    def("modulo") { args in
        let a = try intArg(args[0], "modulo")
        let b = try intArg(args[1], "modulo")
        if b == 0 { throw schemeError("modulo: division by zero") }
        let r = a % b
        return .integer((r != 0 && (r < 0) != (b < 0)) ? r + b : r)
    }
    def("remainder") { args in
        let a = try intArg(args[0], "remainder")
        let b = try intArg(args[1], "remainder")
        if b == 0 { throw schemeError("remainder: division by zero") }
        return .integer(a % b)
    }
    def("quotient") { args in
        let a = try intArg(args[0], "quotient")
        let b = try intArg(args[1], "quotient")
        if b == 0 { throw schemeError("quotient: division by zero") }
        return .integer(a / b)
    }
    def("abs") { args in
        switch args[0] {
        case .integer(let n): return .integer(abs(n))
        case .real(let d): return .real(abs(d))
        case .rational(let n, let d): return makeRational(abs(n), d)
        default: throw schemeError("abs: expected number", [args[0]])
        }
    }
    def("min") { args in
        var best = try asNum(args[0], "min")
        for a in args[1...] {
            let n = try asNum(a, "min")
            if numCompare(n, best) < 0 { best = n }
        }
        return numToValue(best)
    }
    def("max") { args in
        var best = try asNum(args[0], "max")
        for a in args[1...] {
            let n = try asNum(a, "max")
            if numCompare(n, best) > 0 { best = n }
        }
        return numToValue(best)
    }
    def("gcd") { args in
        var acc = 0
        for a in args { acc = gcdInt(acc, try intArg(a, "gcd")) }
        return .integer(acc)
    }
    def("expt") { args in
        if case .integer(let base) = args[0], case .integer(let exp) = args[1], exp >= 0 {
            var result = 1
            var overflow = false
            for _ in 0..<exp {
                let (r, o) = result.multipliedReportingOverflow(by: base)
                if o { overflow = true; break }
                result = r
            }
            if !overflow { return .integer(result) }
        }
        let base = numToDouble(try asNum(args[0], "expt"))
        let exp = numToDouble(try asNum(args[1], "expt"))
        return .real(pow(base, exp))
    }
    def("zero?") { args in .bool(numCompare(try asNum(args[0], "zero?"), .int(0)) == 0) }
    def("positive?") { args in .bool(numCompare(try asNum(args[0], "positive?"), .int(0)) > 0) }
    def("negative?") { args in .bool(numCompare(try asNum(args[0], "negative?"), .int(0)) < 0) }
    def("even?") { args in .bool(try intArg(args[0], "even?") % 2 == 0) }
    def("odd?") { args in .bool(try intArg(args[0], "odd?") % 2 != 0) }
    def("1+") { args in numToValue(numAdd(try asNum(args[0], "1+"), .int(1))) }
    def("1-") { args in numToValue(numSub(try asNum(args[0], "1-"), .int(1))) }
}
