import Foundation

func installBuiltins(into env: Environment, interp: Interpreter) {
    let registry = BuiltinRegistry(env: env)
    installNumeric(registry)
    installLists(registry)
    installStrings(registry)
    installControl(registry)
    installVectors(registry)
    installHashTables(registry)
    installPromises(registry)
    installPorts(registry, interp: interp)
}

private func installLists(_ r: BuiltinRegistry) {
    r.def("cons", .exactly(2)) { args in cons(args[0], args[1]) }
    r.def("car", .exactly(1)) { args in try pairArg(args[0], "car").car }
    r.def("cdr", .exactly(1)) { args in try pairArg(args[0], "cdr").cdr }
    var paths: [String] = []
    var level = ["a", "d"]
    for _ in 2...4 {
        level = level.flatMap { ["a" + $0, "d" + $0] }
        paths += level
    }
    for path in paths {
        let name = "c\(path)r"
        r.def(name, .exactly(1)) { args in
            var current = args[0]
            for step in path.reversed() {
                let p = try pairArg(current, name)
                current = step == "a" ? p.car : p.cdr
            }
            return current
        }
    }
    r.def("set-car!", .exactly(2)) { args in try pairArg(args[0], "set-car!").car = args[1]; return .unspecified }
    r.def("set-cdr!", .exactly(2)) { args in try pairArg(args[0], "set-cdr!").cdr = args[1]; return .unspecified }
    r.def("list", .atLeast(0)) { args in arrayToList(args) }
    r.def("make-list", .between(1, 2)) { args in
        let fill = args.count > 1 ? args[1] : .unspecified
        return arrayToList(Array(repeating: fill, count: try indexArg(args[0], "make-list")))
    }
    r.def("length", .exactly(1)) { args in .integer(try listToArray(args[0]).count) }
    r.def("reverse", .exactly(1)) { args in arrayToList(try listToArray(args[0]).reversed()) }
    r.def("append", .atLeast(0)) { args in
        guard var joined = args.last else { return .null }
        for list in args.dropLast().reversed() {
            joined = arrayToList(try listToArray(list), tail: joined)
        }
        return joined
    }
    r.def("list-tail", .exactly(2)) { args in
        var current = args[0]
        for _ in 0..<(try indexArg(args[1], "list-tail")) {
            guard case .pair(let p) = current else { throw schemeError("list-tail: index out of range") }
            current = p.cdr
        }
        return current
    }
    r.def("list-ref", .exactly(2)) { args in
        let elements = try listToArray(args[0])
        let i = try indexArg(args[1], "list-ref")
        guard i < elements.count else { throw schemeError("list-ref: index out of range", [args[1]]) }
        return elements[i]
    }
    r.def("list-copy", .exactly(1)) { args in
        let (elements, tail) = listToArrayWithTail(args[0])
        return arrayToList(elements, tail: tail)
    }
    r.def("last-pair", .exactly(1)) { args in
        var p = try pairArg(args[0], "last-pair")
        while case .pair(let next) = p.cdr { p = next }
        return .pair(p)
    }

    func memberBy(_ name: String, _ same: @escaping (Value, Value) -> Bool) {
        r.def(name, .exactly(2)) { args in
            var current = args[1]
            while case .pair(let p) = current {
                if same(args[0], p.car) { return current }
                current = p.cdr
            }
            return .bool(false)
        }
    }
    memberBy("member", equalValues)
    memberBy("memq", eqv)
    memberBy("memv", eqv)

    func assocBy(_ name: String, _ same: @escaping (Value, Value) -> Bool) {
        r.def(name, .exactly(2)) { args in
            var current = args[1]
            while case .pair(let p) = current {
                if case .pair(let entry) = p.car, same(args[0], entry.car) { return p.car }
                current = p.cdr
            }
            return .bool(false)
        }
    }
    assocBy("assoc", equalValues)
    assocBy("assq", eqv)
    assocBy("assv", eqv)

    r.predicate("null?") { if case .null = $0 { return true }; return false }
    r.predicate("pair?") { if case .pair = $0 { return true }; return false }
    r.predicate("list?") { isProperList($0) }
    r.predicate("symbol?") { if case .symbol = $0 { return true }; return false }
    r.predicate("boolean?") { if case .bool = $0 { return true }; return false }
    r.predicate("procedure?") { isProcedure($0) }
    r.def("not", .exactly(1)) { args in .bool(!isTruthy(args[0])) }
    r.def("eq?", .exactly(2)) { args in .bool(eqv(args[0], args[1])) }
    r.def("eqv?", .exactly(2)) { args in .bool(eqv(args[0], args[1])) }
    r.def("equal?", .exactly(2)) { args in .bool(equalValues(args[0], args[1])) }
}

private func installStrings(_ r: BuiltinRegistry) {
    r.predicate("string?") { if case .string = $0 { return true }; return false }
    r.predicate("char?") { if case .char = $0 { return true }; return false }
    r.def("string-length", .exactly(1)) { args in .integer(try stringArg(args[0], "string-length").count) }
    r.def("string-ref", .exactly(2)) { args in
        let chars = Array(try stringArg(args[0], "string-ref"))
        let i = try indexArg(args[1], "string-ref")
        guard i < chars.count else { throw schemeError("string-ref: index out of range", [args[1]]) }
        return .char(chars[i])
    }
    r.def("string-append", .atLeast(0)) { args in
        .string(try args.map { try stringArg($0, "string-append") }.joined())
    }
    r.def("substring", .between(2, 3)) { args in
        let chars = Array(try stringArg(args[0], "substring"))
        return .string(String(chars[try rangeArgs(args, from: 1, count: chars.count, "substring")]))
    }
    r.def("string-copy", .between(1, 3)) { args in
        let chars = Array(try stringArg(args[0], "string-copy"))
        return .string(String(chars[try rangeArgs(args, from: 1, count: chars.count, "string-copy")]))
    }
    r.def("make-string", .between(1, 2)) { args in
        let fill = args.count > 1 ? try charArg(args[1], "make-string") : " "
        return .string(String(repeating: fill, count: try indexArg(args[0], "make-string")))
    }
    r.def("string", .atLeast(0)) { args in .string(String(try args.map { try charArg($0, "string") })) }
    r.def("string->list", .between(1, 3)) { args in
        let chars = Array(try stringArg(args[0], "string->list"))
        return arrayToList(chars[try rangeArgs(args, from: 1, count: chars.count, "string->list")].map { .char($0) })
    }
    r.def("list->string", .exactly(1)) { args in
        .string(String(try listToArray(args[0]).map { try charArg($0, "list->string") }))
    }
    r.def("string-upcase", .exactly(1)) { args in .string(try stringArg(args[0], "string-upcase").uppercased()) }
    r.def("string-downcase", .exactly(1)) { args in .string(try stringArg(args[0], "string-downcase").lowercased()) }

    func stringCompare(_ name: String, foldCase: Bool, _ holds: @escaping (String, String) -> Bool) {
        r.def(name, .atLeast(1)) { args in
            let texts = try args.map { foldCase ? try stringArg($0, name).lowercased() : try stringArg($0, name) }
            return .bool(zip(texts, texts.dropFirst()).allSatisfy { holds($0, $1) })
        }
    }
    stringCompare("string=?", foldCase: false, ==)
    stringCompare("string<?", foldCase: false, <)
    stringCompare("string>?", foldCase: false, >)
    stringCompare("string<=?", foldCase: false, <=)
    stringCompare("string>=?", foldCase: false, >=)
    stringCompare("string-ci=?", foldCase: true, ==)

    r.def("string->symbol", .exactly(1)) { args in .symbol(try stringArg(args[0], "string->symbol")) }
    r.def("symbol->string", .exactly(1)) { args in .string(try symbolArg(args[0], "symbol->string")) }

    r.def("char->integer", .exactly(1)) { args in
        let c = try charArg(args[0], "char->integer")
        return .integer(Int(c.unicodeScalars.first!.value))
    }
    r.def("integer->char", .exactly(1)) { args in
        guard let scalar = Unicode.Scalar(UInt32(clamping: try indexArg(args[0], "integer->char"))) else {
            throw schemeError("integer->char: not a Unicode scalar value", [args[0]])
        }
        return .char(Character(scalar))
    }

    func charCompare(_ name: String, _ holds: @escaping (Character, Character) -> Bool) {
        r.def(name, .atLeast(1)) { args in
            let chars = try args.map { try charArg($0, name) }
            return .bool(zip(chars, chars.dropFirst()).allSatisfy { holds($0, $1) })
        }
    }
    charCompare("char=?", ==)
    charCompare("char<?", <)
    charCompare("char>?", >)
    charCompare("char<=?", <=)
    charCompare("char>=?", >=)

    func charTest(_ name: String, _ test: @escaping (Character) -> Bool) {
        r.def(name, .exactly(1)) { args in .bool(test(try charArg(args[0], name))) }
    }
    charTest("char-alphabetic?") { $0.isLetter }
    charTest("char-numeric?") { $0.isNumber }
    charTest("char-whitespace?") { $0.isWhitespace }
    charTest("char-upper-case?") { $0.isUppercase }
    charTest("char-lower-case?") { $0.isLowercase }
    r.def("char-upcase", .exactly(1)) { args in .char(Character(try charArg(args[0], "char-upcase").uppercased())) }
    r.def("char-downcase", .exactly(1)) { args in .char(Character(try charArg(args[0], "char-downcase").lowercased())) }
    r.def("digit-value", .exactly(1)) { args in
        let c = try charArg(args[0], "digit-value")
        guard c.isNumber, let digit = c.wholeNumberValue else { return .bool(false) }
        return .integer(digit)
    }
}

private func installControl(_ r: BuiltinRegistry) {
    r.def("apply", .atLeast(2), .apply)
    r.def("call/cc", .exactly(1), .callCC)
    r.def("call-with-current-continuation", .exactly(1), .callCC)
    r.def("values", .atLeast(0), .values)
    r.def("call-with-values", .exactly(2), .callWithValues)
    r.def("dynamic-wind", .exactly(3), .dynamicWind)
    r.def("with-exception-handler", .exactly(2), .withExceptionHandler)
    r.def("raise", .exactly(1), .raise)
    r.def("raise-continuable", .exactly(1), .raiseContinuable)

    r.def("error", .atLeast(1)) { args in
        let message: String
        if case .string(let text) = args[0] { message = text } else { message = writeString(args[0]) }
        let irritants = Array(args.dropFirst())
        throw SchemeError(message, irritants: irritants,
                          condition: .errorObject(ErrorObject(message: message, irritants: irritants)))
    }
    r.predicate("error-object?") { if case .errorObject = $0 { return true }; return false }
    r.def("error-object-message", .exactly(1)) { args in
        .string(try errorObjectArg(args[0], "error-object-message").message)
    }
    r.def("error-object-irritants", .exactly(1)) { args in
        arrayToList(try errorObjectArg(args[0], "error-object-irritants").irritants)
    }
    r.predicate("read-error?") { if case .errorObject(let e) = $0 { return e.kind == .read }; return false }
    r.predicate("file-error?") { if case .errorObject(let e) = $0 { return e.kind == .file }; return false }
}
