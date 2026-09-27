func sym(_ name: String) -> Value { .symbol(name) }
func core(_ name: String) -> Value { .symbol(name + String(hygieneMark) + rootScopeMark) }
func listV(_ items: [Value]) -> Value { arrayToList(items) }
func quoteExpr(_ v: Value) -> Value { listV([core("quote"), v]) }

func cadrOf(_ form: Value) throws -> Value {
    let parts = try listToArray(form)
    guard parts.count >= 2 else { throw schemeError("malformed form", [form]) }
    return parts[1]
}

private func bindingParts(_ bindings: [Value]) throws -> (vars: [Value], inits: [Value]) {
    var vars: [Value] = []
    var inits: [Value] = []
    for b in bindings {
        let bp = try listToArray(b)
        guard let variable = bp.first else { throw schemeError("malformed binding") }
        vars.append(variable)
        inits.append(bp.count > 1 ? bp[1] : .unspecified)
    }
    return (vars, inits)
}

func desugarLet(_ form: Value, _ gensym: Gensym) throws -> Value {
    let elems = try listToArray(form)
    guard elems.count >= 3 else { throw schemeError("malformed let") }
    if case .symbol(let name) = elems[1] {
        let (vars, inits) = try bindingParts(try listToArray(elems[2]))
        let lambdaExpr = listV([core("lambda"), listV(vars)] + Array(elems[3...]))
        let letrecBindings = listV([listV([sym(name), lambdaExpr])])
        let call = listV([sym(name)] + inits)
        return listV([core("letrec"), letrecBindings, call])
    }
    let (vars, inits) = try bindingParts(try listToArray(elems[1]))
    let lambdaExpr = listV([core("lambda"), listV(vars)] + Array(elems[2...]))
    return listV([lambdaExpr] + inits)
}

func desugarLetStar(_ form: Value) throws -> Value {
    let elems = try listToArray(form)
    guard elems.count >= 3 else { throw schemeError("malformed let*") }
    let bindings = try listToArray(elems[1])
    let body = Array(elems[2...])
    if bindings.isEmpty {
        return listV([listV([core("lambda"), .null] + body)])
    }
    let inner = listV([core("let*"), listV(Array(bindings[1...]))] + body)
    return listV([core("let"), listV([bindings[0]]), inner])
}

func desugarLetrec(_ form: Value) throws -> Value {
    let elems = try listToArray(form)
    guard elems.count >= 3 else { throw schemeError("malformed letrec") }
    let (vars, inits) = try bindingParts(try listToArray(elems[1]))
    let setExprs = zip(vars, inits).map { listV([core("set!"), $0, $1]) }
    let lambdaExpr = listV([core("lambda"), listV(vars)] + setExprs + Array(elems[2...]))
    return listV([lambdaExpr] + vars.map { _ in Value.unspecified })
}

func desugarCond(_ form: Value, _ gensym: Gensym) throws -> Value {
    let clauses = Array(try listToArray(form)[1...])
    var result: Value = .unspecified
    for clause in clauses.reversed() {
        let parts = try listToArray(clause)
        guard let test = parts.first else { throw schemeError("empty cond clause") }
        if case .symbol(let s) = test, baseName(s) == "else" {
            result = listV([core("begin")] + Array(parts[1...]))
        } else if parts.count >= 3, case .symbol(let arrow) = parts[1], baseName(arrow) == "=>" {
            let temp = freshTemp(gensym)
            result = listV([
                core("let"), listV([listV([sym(temp), test])]),
                listV([core("if"), sym(temp), listV([parts[2], sym(temp)]), result]),
            ])
        } else if parts.count == 1 {
            let temp = freshTemp(gensym)
            result = listV([
                core("let"), listV([listV([sym(temp), test])]),
                listV([core("if"), sym(temp), sym(temp), result]),
            ])
        } else {
            let thenExpr = listV([core("begin")] + Array(parts[1...]))
            result = listV([core("if"), test, thenExpr, result])
        }
    }
    return result
}

func desugarCase(_ form: Value, _ gensym: Gensym) throws -> Value {
    let parts = try listToArray(form)
    guard parts.count >= 2 else { throw schemeError("malformed case") }
    let temp = freshTemp(gensym)
    var condClauses: [Value] = []
    for clause in parts[2...] {
        let cparts = try listToArray(clause)
        guard let head = cparts.first else { throw schemeError("empty case clause") }
        if case .symbol(let s) = head, baseName(s) == "else" {
            condClauses.append(listV([core("else")] + Array(cparts[1...])))
        } else {
            let test = listV([core("memv"), sym(temp), quoteExpr(head)])
            condClauses.append(listV([test] + Array(cparts[1...])))
        }
    }
    let condForm = listV([core("cond")] + condClauses)
    return listV([core("let"), listV([listV([sym(temp), parts[1]])]), condForm])
}

func desugarAnd(_ form: Value) throws -> Value {
    let parts = Array(try listToArray(form)[1...])
    func andOf(_ xs: [Value]) -> Value {
        if xs.isEmpty { return .bool(true) }
        if xs.count == 1 { return xs[0] }
        return listV([core("if"), xs[0], andOf(Array(xs[1...])), .bool(false)])
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
            core("let"), listV([listV([sym(temp), xs[0]])]),
            listV([core("if"), sym(temp), sym(temp), orOf(Array(xs[1...]))]),
        ])
    }
    return orOf(parts)
}

func desugarDo(_ form: Value, _ gensym: Gensym) throws -> Value {
    let parts = try listToArray(form)
    guard parts.count >= 3 else { throw schemeError("malformed do") }
    var vars: [Value] = []
    var inits: [Value] = []
    var steps: [Value] = []
    for spec in try listToArray(parts[1]) {
        let sp = try listToArray(spec)
        guard let variable = sp.first, case .symbol = variable else { throw schemeError("bad do binding") }
        vars.append(variable)
        inits.append(sp.count >= 2 ? sp[1] : .unspecified)
        steps.append(sp.count >= 3 ? sp[2] : variable)
    }
    let testClause = try listToArray(parts[2])
    guard let test = testClause.first else { throw schemeError("malformed do test clause") }
    let loopName = freshTemp(gensym)
    let recur = listV([sym(loopName)] + steps)
    let loopBody = listV([core("begin")] + Array(parts[3...]) + [recur])
    let finish = listV([core("begin")] + Array(testClause.dropFirst()))
    let loopLambda = listV([core("lambda"), listV(vars), listV([core("if"), test, finish, loopBody])])
    let letrecBindings = listV([listV([sym(loopName), loopLambda])])
    return listV([core("letrec"), letrecBindings, listV([sym(loopName)] + inits)])
}

private func formalVariables(_ formals: Value) throws -> [Value] {
    let (elements, tail) = listToArrayWithTail(formals)
    var variables = elements
    switch tail {
    case .null: break
    case .symbol: variables.append(tail)
    default: throw schemeError("bad formals", [formals])
    }
    guard variables.allSatisfy({ if case .symbol = $0 { return true }; return false }) else {
        throw schemeError("bad formals", [formals])
    }
    return variables
}

private func renamedFormals(_ formals: Value, _ gensym: Gensym) throws -> (formals: Value, temps: [Value]) {
    let (elements, tail) = listToArrayWithTail(formals)
    _ = try formalVariables(formals)
    let temps = elements.map { _ in sym(freshTemp(gensym)) }
    if case .symbol = tail {
        let restTemp = sym(freshTemp(gensym))
        return (arrayToList(temps, tail: restTemp), temps + [restTemp])
    }
    return (arrayToList(temps), temps)
}

private func receiveValues(_ formals: Value, _ producer: Value, _ body: Value) -> Value {
    listV([core("call-with-values"), listV([core("lambda"), .null, producer]), listV([core("lambda"), formals, body])])
}

func desugarLetValues(_ form: Value, _ gensym: Gensym) throws -> Value {
    let parts = try listToArray(form)
    guard parts.count >= 3 else { throw schemeError("malformed let-values") }
    let clauses = try listToArray(parts[1]).map { try listToArray($0) }
    var bindings: [Value] = []
    var steps: [(formals: Value, producer: Value)] = []
    for clause in clauses {
        guard clause.count == 2 else { throw schemeError("malformed let-values binding") }
        let (temporary, temps) = try renamedFormals(clause[0], gensym)
        for (variable, temp) in zip(try formalVariables(clause[0]), temps) {
            bindings.append(listV([variable, temp]))
        }
        steps.append((temporary, clause[1]))
    }
    var result = listV([core("let"), listV(bindings)] + Array(parts[2...]))
    for step in steps.reversed() {
        result = receiveValues(step.formals, step.producer, result)
    }
    return result
}

func desugarLetStarValues(_ form: Value) throws -> Value {
    let parts = try listToArray(form)
    guard parts.count >= 3 else { throw schemeError("malformed let*-values") }
    var result = listV([core("let"), .null] + Array(parts[2...]))
    for clause in try listToArray(parts[1]).reversed() {
        let clauseParts = try listToArray(clause)
        guard clauseParts.count == 2 else { throw schemeError("malformed let*-values binding") }
        _ = try formalVariables(clauseParts[0])
        result = receiveValues(clauseParts[0], clauseParts[1], result)
    }
    return result
}

func desugarDefineValues(_ form: Value, _ gensym: Gensym) throws -> Value {
    let parts = try listToArray(form)
    guard parts.count == 3 else { throw schemeError("malformed define-values") }
    let variables = try formalVariables(parts[1])
    let (temporary, temps) = try renamedFormals(parts[1], gensym)
    let declarations = variables.map { listV([core("define"), $0]) }
    let assignments = zip(variables, temps).map { listV([core("set!"), $0, $1]) }
    let assign = listV([core("lambda"), temporary] + assignments)
    let call = listV([core("call-with-values"), listV([core("lambda"), .null, parts[2]]), assign])
    return listV([core("begin")] + declarations + [call])
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
            return listV([core("cons"), quoteExpr(sym("unquote")), expandQuasi(p.cdr, depth - 1)])
        }
        if case .symbol(let s) = p.car, baseName(s) == "quasiquote" {
            return listV([core("cons"), quoteExpr(sym("quasiquote")), expandQuasi(p.cdr, depth + 1)])
        }
        if case .pair(let carp) = p.car, case .symbol(let s) = carp.car, baseName(s) == "unquote-splicing", depth == 1 {
            let spliced: Value
            if case .pair(let inner) = carp.cdr { spliced = inner.car } else { spliced = .null }
            return listV([core("append"), spliced, expandQuasi(p.cdr, depth)])
        }
        return listV([core("cons"), expandQuasi(p.car, depth), expandQuasi(p.cdr, depth)])
    case .vector(let v):
        let asList = expandQuasi(arrayToList(v.items), depth)
        return listV([core("list->vector"), asList])
    case .null:
        return quoteExpr(.null)
    case .symbol:
        return quoteExpr(template)
    default:
        return template
    }
}
