func sym(_ name: String) -> Value { .symbol(name) }
func listV(_ items: [Value]) -> Value { arrayToList(items) }
func quoteExpr(_ v: Value) -> Value { listV([sym("quote"), v]) }

func cadrOf(_ form: Value) throws -> Value {
    let parts = try listToArray(form)
    guard parts.count >= 2 else { throw schemeError("malformed form", [form]) }
    return parts[1]
}

func desugarLet(_ form: Value, _ gensym: Gensym) throws -> Value {
    let elems = try listToArray(form)
    guard elems.count >= 3 else { throw schemeError("malformed let") }
    if case .symbol(let name) = elems[1] {
        let bindings = try listToArray(elems[2])
        let body = Array(elems[3...])
        var vars: [Value] = []
        var inits: [Value] = []
        for b in bindings {
            let bp = try listToArray(b)
            vars.append(bp[0])
            inits.append(bp.count > 1 ? bp[1] : .unspecified)
        }
        let lambdaExpr = listV([sym("lambda"), listV(vars)] + body)
        let letrecBindings = listV([listV([sym(name), lambdaExpr])])
        let call = listV([sym(name)] + inits)
        return listV([sym("letrec"), letrecBindings, call])
    }
    let bindings = try listToArray(elems[1])
    let body = Array(elems[2...])
    var vars: [Value] = []
    var inits: [Value] = []
    for b in bindings {
        let bp = try listToArray(b)
        vars.append(bp[0])
        inits.append(bp.count > 1 ? bp[1] : .unspecified)
    }
    let lambdaExpr = listV([sym("lambda"), listV(vars)] + body)
    return listV([lambdaExpr] + inits)
}

func desugarLetStar(_ form: Value) throws -> Value {
    let elems = try listToArray(form)
    let bindings = try listToArray(elems[1])
    let body = Array(elems[2...])
    if bindings.isEmpty {
        return listV([listV([sym("lambda"), .null] + body)])
    }
    let first = bindings[0]
    let rest = Array(bindings[1...])
    let inner = listV([sym("let*"), listV(rest)] + body)
    return listV([sym("let"), listV([first]), inner])
}

func desugarLetrec(_ form: Value) throws -> Value {
    let elems = try listToArray(form)
    let bindings = try listToArray(elems[1])
    let body = Array(elems[2...])
    var vars: [Value] = []
    var setExprs: [Value] = []
    for b in bindings {
        let bp = try listToArray(b)
        vars.append(bp[0])
        setExprs.append(listV([sym("set!"), bp[0], bp.count > 1 ? bp[1] : .unspecified]))
    }
    let lambdaBody = setExprs + body
    let lambdaExpr = listV([sym("lambda"), listV(vars)] + lambdaBody)
    let args = vars.map { _ in Value.unspecified }
    return listV([lambdaExpr] + args)
}

func desugarCond(_ form: Value, _ gensym: Gensym) throws -> Value {
    let clauses = Array(try listToArray(form)[1...])
    var result: Value = .unspecified
    for clause in clauses.reversed() {
        let parts = try listToArray(clause)
        guard let test = parts.first else { throw schemeError("empty cond clause") }
        if case .symbol(let s) = test, baseName(s) == "else" {
            result = listV([sym("begin")] + Array(parts[1...]))
        } else if parts.count >= 3, case .symbol(let arrow) = parts[1], baseName(arrow) == "=>" {
            let temp = freshTemp(gensym)
            result = listV([
                sym("let"), listV([listV([sym(temp), test])]),
                listV([sym("if"), sym(temp), listV([parts[2], sym(temp)]), result]),
            ])
        } else if parts.count == 1 {
            let temp = freshTemp(gensym)
            result = listV([
                sym("let"), listV([listV([sym(temp), test])]),
                listV([sym("if"), sym(temp), sym(temp), result]),
            ])
        } else {
            let thenExpr = listV([sym("begin")] + Array(parts[1...]))
            result = listV([sym("if"), test, thenExpr, result])
        }
    }
    return result
}

func desugarCase(_ form: Value, _ gensym: Gensym) throws -> Value {
    let parts = try listToArray(form)
    let key = parts[1]
    let clauses = Array(parts[2...])
    let temp = freshTemp(gensym)
    var condClauses: [Value] = []
    for clause in clauses {
        let cparts = try listToArray(clause)
        if case .symbol(let s) = cparts[0], baseName(s) == "else" {
            condClauses.append(listV([sym("else")] + Array(cparts[1...])))
        } else {
            let test = listV([sym("memv"), sym(temp), quoteExpr(cparts[0])])
            condClauses.append(listV([test] + Array(cparts[1...])))
        }
    }
    let condForm = listV([sym("cond")] + condClauses)
    return listV([sym("let"), listV([listV([sym(temp), key])]), condForm])
}

func desugarAnd(_ form: Value) throws -> Value {
    let parts = Array(try listToArray(form)[1...])
    func andOf(_ xs: [Value]) -> Value {
        if xs.isEmpty { return .bool(true) }
        if xs.count == 1 { return xs[0] }
        return listV([sym("if"), xs[0], andOf(Array(xs[1...])), .bool(false)])
    }
    return andOf(parts)
}

func desugarOr(_ form: Value, _ gensym: Gensym) throws -> Value {
    let parts = Array(try listToArray(form)[1...])
    func orOf(_ xs: [Value]) -> Value {
        if xs.isEmpty { return .bool(false) }
        if xs.count == 1 { return xs[0] }
        let temp = freshTemp(gensym)
        return listV([
            sym("let"), listV([listV([sym(temp), xs[0]])]),
            listV([sym("if"), sym(temp), sym(temp), orOf(Array(xs[1...]))]),
        ])
    }
    return orOf(parts)
}

func freshTemp(_ gensym: Gensym) -> String {
    "t" + String(hygieneMark) + "d" + String(gensym.next())
}

func expandQuasi(_ template: Value, _ depth: Int) -> Value {
    switch template {
    case .pair(let p):
        if case .symbol(let s) = p.car, baseName(s) == "unquote" {
            if depth == 1 {
                if case .pair(let inner) = p.cdr { return inner.car }
                return .unspecified
            }
            return listV([sym("cons"), quoteExpr(sym("unquote")), expandQuasi(p.cdr, depth - 1)])
        }
        if case .symbol(let s) = p.car, baseName(s) == "quasiquote" {
            return listV([sym("cons"), quoteExpr(sym("quasiquote")), expandQuasi(p.cdr, depth + 1)])
        }
        if case .pair(let carp) = p.car, case .symbol(let s) = carp.car, baseName(s) == "unquote-splicing", depth == 1 {
            let spliced: Value
            if case .pair(let inner) = carp.cdr { spliced = inner.car } else { spliced = .null }
            return listV([sym("append"), spliced, expandQuasi(p.cdr, depth)])
        }
        return listV([sym("cons"), expandQuasi(p.car, depth), expandQuasi(p.cdr, depth)])
    case .null:
        return quoteExpr(.null)
    case .symbol:
        return quoteExpr(template)
    default:
        return template
    }
}
