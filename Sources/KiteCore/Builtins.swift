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

    def("cons") { args in cons(args[0], args[1]) }
    func pairArg(_ v: Value, _ who: String) throws -> Pair {
        guard case .pair(let p) = v else { throw schemeError("\(who): expected pair", [v]) }
        return p
    }
    def("car") { args in try pairArg(args[0], "car").car }
    def("cdr") { args in try pairArg(args[0], "cdr").cdr }
    def("caar") { args in try pairArg(try pairArg(args[0], "caar").car, "caar").car }
    def("cadr") { args in try pairArg(try pairArg(args[0], "cadr").cdr, "cadr").car }
    def("cdar") { args in try pairArg(try pairArg(args[0], "cdar").car, "cdar").cdr }
    def("cddr") { args in try pairArg(try pairArg(args[0], "cddr").cdr, "cddr").cdr }
    def("caddr") { args in
        let d = try pairArg(args[0], "caddr").cdr
        let dd = try pairArg(d, "caddr").cdr
        return try pairArg(dd, "caddr").car
    }
    def("cadddr") { args in
        let d = try pairArg(args[0], "cadddr").cdr
        let dd = try pairArg(d, "cadddr").cdr
        let ddd = try pairArg(dd, "cadddr").cdr
        return try pairArg(ddd, "cadddr").car
    }
    def("set-car!") { args in try pairArg(args[0], "set-car!").car = args[1]; return .unspecified }
    def("set-cdr!") { args in try pairArg(args[0], "set-cdr!").cdr = args[1]; return .unspecified }
    def("list") { args in arrayToList(args) }
    def("length") { args in .integer(try listToArray(args[0]).count) }
    def("reverse") { args in arrayToList(try listToArray(args[0]).reversed()) }
    def("append") { args in
        if args.isEmpty { return .null }
        var result = args[args.count - 1]
        for list in args[0..<(args.count - 1)].reversed() {
            let items = try listToArray(list)
            result = arrayToList(items, tail: result)
        }
        return result
    }
    def("list-ref") { args in
        let items = try listToArray(args[0])
        let i = try intArg(args[1], "list-ref")
        guard i >= 0, i < items.count else { throw schemeError("list-ref: index out of range") }
        return items[i]
    }
    def("list-tail") { args in
        var cur = args[0]
        let k = try intArg(args[1], "list-tail")
        for _ in 0..<k {
            guard case .pair(let p) = cur else { throw schemeError("list-tail: index out of range") }
            cur = p.cdr
        }
        return cur
    }
    def("list-copy") { args in arrayToList(try listToArray(args[0])) }

    def("map") { args in
        let proc = args[0]
        let lists = try args[1...].map { try listToArray($0) }
        let n = lists.map { $0.count }.min() ?? 0
        var out: [Value] = []
        for i in 0..<n {
            out.append(try interp.applyProcedure(proc, lists.map { $0[i] }))
        }
        return arrayToList(out)
    }
    def("for-each") { args in
        let proc = args[0]
        let lists = try args[1...].map { try listToArray($0) }
        let n = lists.map { $0.count }.min() ?? 0
        for i in 0..<n {
            _ = try interp.applyProcedure(proc, lists.map { $0[i] })
        }
        return .unspecified
    }
    def("filter") { args in
        let proc = args[0]
        var out: [Value] = []
        for item in try listToArray(args[1]) where isTruthy(try interp.applyProcedure(proc, [item])) {
            out.append(item)
        }
        return arrayToList(out)
    }
    def("fold-left") { args in
        let proc = args[0]
        var acc = args[1]
        for item in try listToArray(args[2]) {
            acc = try interp.applyProcedure(proc, [acc, item])
        }
        return acc
    }
    def("fold-right") { args in
        let proc = args[0]
        var acc = args[1]
        for item in try listToArray(args[2]).reversed() {
            acc = try interp.applyProcedure(proc, [item, acc])
        }
        return acc
    }

    func memberBy(_ pred: @escaping (Value, Value) -> Bool) -> ([Value]) throws -> Value {
        return { args in
            var cur = args[1]
            while case .pair(let p) = cur {
                if pred(args[0], p.car) { return cur }
                cur = p.cdr
            }
            return .bool(false)
        }
    }
    def("member", .none, memberBy(equalValues))
    def("memq", .none, memberBy(eqv))
    def("memv", .none, memberBy(eqv))

    func assocBy(_ pred: @escaping (Value, Value) -> Bool) -> ([Value]) throws -> Value {
        return { args in
            var cur = args[1]
            while case .pair(let p) = cur {
                if case .pair(let entry) = p.car, pred(args[0], entry.car) { return p.car }
                cur = p.cdr
            }
            return .bool(false)
        }
    }
    def("assoc", .none, assocBy(equalValues))
    def("assq", .none, assocBy(eqv))
    def("assv", .none, assocBy(eqv))

    def("null?") { args in if case .null = args[0] { return .bool(true) }; return .bool(false) }
    def("pair?") { args in if case .pair = args[0] { return .bool(true) }; return .bool(false) }
    def("list?") { args in .bool(isProperList(args[0])) }
    def("symbol?") { args in if case .symbol = args[0] { return .bool(true) }; return .bool(false) }
    def("string?") { args in if case .string = args[0] { return .bool(true) }; return .bool(false) }
    def("char?") { args in if case .char = args[0] { return .bool(true) }; return .bool(false) }
    def("boolean?") { args in if case .bool = args[0] { return .bool(true) }; return .bool(false) }
    def("number?") { args in
        switch args[0] {
        case .integer, .rational, .real: return .bool(true)
        default: return .bool(false)
        }
    }
    def("integer?") { args in if case .integer = args[0] { return .bool(true) }; return .bool(false) }
    def("procedure?") { args in
        switch args[0] {
        case .builtin, .closure, .continuation: return .bool(true)
        default: return .bool(false)
        }
    }
    def("not") { args in .bool(!isTruthy(args[0])) }
    def("eq?") { args in .bool(eqv(args[0], args[1])) }
    def("eqv?") { args in .bool(eqv(args[0], args[1])) }
    def("equal?") { args in .bool(equalValues(args[0], args[1])) }

    def("display") { [weak interp] args in interp?.output(displayString(args[0])); return .unspecified }
    def("write") { [weak interp] args in interp?.output(writeString(args[0])); return .unspecified }
    def("newline") { [weak interp] _ in interp?.output("\n"); return .unspecified }
    def("error") { args in
        let message: String
        if let first = args.first, case .string(let s) = first { message = s }
        else if let first = args.first { message = writeString(first) }
        else { message = "error" }
        throw schemeError(message, Array(args.dropFirst()))
    }

    def("apply", .apply) { _ in .unspecified }
    def("call-with-current-continuation", .callCC) { _ in .unspecified }
    def("call/cc", .callCC) { _ in .unspecified }

    def("string-length") { args in
        guard case .string(let s) = args[0] else { throw schemeError("string-length: expected string") }
        return .integer(s.count)
    }
    def("string-append") { args in
        var out = ""
        for a in args {
            guard case .string(let s) = a else { throw schemeError("string-append: expected string") }
            out += s
        }
        return .string(out)
    }
    def("substring") { args in
        guard case .string(let s) = args[0] else { throw schemeError("substring: expected string") }
        let chars = Array(s)
        let start = try intArg(args[1], "substring")
        let end = args.count > 2 ? try intArg(args[2], "substring") : chars.count
        guard start >= 0, end <= chars.count, start <= end else { throw schemeError("substring: range error") }
        return .string(String(chars[start..<end]))
    }
    def("string=?") { args in
        guard case .string(let a) = args[0], case .string(let b) = args[1] else {
            throw schemeError("string=?: expected strings")
        }
        return .bool(a == b)
    }
    def("string->symbol") { args in
        guard case .string(let s) = args[0] else { throw schemeError("string->symbol: expected string") }
        return .symbol(s)
    }
    def("symbol->string") { args in
        guard case .symbol(let s) = args[0] else { throw schemeError("symbol->string: expected symbol") }
        return .string(baseName(s))
    }
    def("number->string") { args in .string(displayString(args[0])) }
    def("string->number") { args in
        guard case .string(let s) = args[0] else { throw schemeError("string->number: expected string") }
        if let n = parseInteger(s) { return .integer(n) }
        if let rat = parseRational(s) { return rat }
        if let d = parseReal(s) { return .real(d) }
        return .bool(false)
    }
    def("char->integer") { args in
        guard case .char(let c) = args[0], let scalar = c.unicodeScalars.first else {
            throw schemeError("char->integer: expected char")
        }
        return .integer(Int(scalar.value))
    }
    def("integer->char") { args in
        let n = try intArg(args[0], "integer->char")
        guard let scalar = Unicode.Scalar(UInt32(n)) else { throw schemeError("integer->char: out of range") }
        return .char(Character(scalar))
    }
    def("char=?") { args in
        guard case .char(let a) = args[0], case .char(let b) = args[1] else {
            throw schemeError("char=?: expected chars")
        }
        return .bool(a == b)
    }

    def("exact->inexact") { args in .real(numToDouble(try asNum(args[0], "exact->inexact"))) }
    def("inexact->exact") { args in
        switch args[0] {
        case .integer, .rational: return args[0]
        case .real(let d):
            if d == d.rounded() { return .integer(Int(d)) }
            return args[0]
        default: throw schemeError("inexact->exact: expected number")
        }
    }
}
