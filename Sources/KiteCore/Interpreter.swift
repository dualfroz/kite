public final class Interpreter {
    public let globalEnv: Environment
    let gensym: Gensym
    public var output: (String) -> Void

    public init() {
        self.globalEnv = Environment()
        self.gensym = Gensym()
        self.output = { Swift.print($0, terminator: "") }
        installBuiltins(into: globalEnv, interp: self)
        loadPrelude()
    }

    public func evalTop(_ expr: Value) throws -> Value {
        try run(.evaluating(expr, globalEnv, .done))
    }

    @discardableResult
    public func evalString(_ source: String) throws -> Value {
        let forms = try Reader(source).readProgram()
        var last: Value = .unspecified
        for form in forms {
            last = try evalTop(form)
        }
        return last
    }

    func applyProcedure(_ proc: Value, _ args: [Value]) throws -> Value {
        try run(.applying(proc, args, .done))
    }

    private func loadPrelude() {
        do {
            try evalString(preludeSource)
        } catch {
            fatalError("prelude failed to load: \(error)")
        }
    }

    private func run(_ initial: MachineState) throws -> Value {
        var state = initial
        while true {
            switch state {
            case .returning(let value, let kont):
                if case .done = kont { return value }
                state = try applyKont(value, kont)
            case .evaluating(let expr, let env, let kont):
                state = try step(expr, env, kont)
            case .applying(let proc, let args, let kont):
                state = try apply(proc, args, kont)
            }
        }
    }

    private func applyKont(_ value: Value, _ kont: Kont) throws -> MachineState {
        switch kont {
        case .done:
            return .returning(value, .done)
        case .ifK(let then, let els, let env, let next):
            if isTruthy(value) { return .evaluating(then, env, next) }
            if let e = els { return .evaluating(e, env, next) }
            return .returning(.unspecified, next)
        case .defineK(let name, let env, let next):
            if case .closure(let lam) = value, lam.name == "lambda" {
                lam.name = baseName(name)
            }
            env.define(name, value)
            return .returning(.unspecified, next)
        case .setK(let name, let env, let next):
            if !env.set(name, value) {
                throw schemeError("set!: unbound variable: \(baseName(name))")
            }
            return .returning(.unspecified, next)
        case .argsK(let pending, let accumulated, let env, let next):
            var acc = accumulated
            acc.append(value)
            if case .pair(let p) = pending {
                return .evaluating(p.car, env, .argsK(pending: p.cdr, accumulated: acc, env: env, next))
            }
            let proc = acc[0]
            let args = Array(acc[1...])
            return .applying(proc, args, next)
        case .seqK(let remaining, let env, let next):
            return seqState(remaining, env, next)
        }
    }

    private func step(_ expr: Value, _ env: Environment, _ kont: Kont) throws -> MachineState {
        switch expr {
        case .symbol(let name):
            guard let value = env.get(name) else {
                throw schemeError("unbound variable: \(baseName(name))")
            }
            if case .syntax = value {
                throw schemeError("syntactic keyword used as variable: \(baseName(name))")
            }
            return .returning(value, kont)
        case .null:
            throw schemeError("cannot evaluate empty list ()")
        case .pair(let p):
            if case .symbol(let s) = p.car {
                let base = baseName(s)
                if let head = env.get(s) {
                    if case .syntax(let rules) = head {
                        let expanded = try rules.expand(expr, gensym)
                        return .evaluating(expanded, env, kont)
                    }
                } else if let special = try specialForm(base, expr, env, kont) {
                    return special
                }
            }
            return .evaluating(p.car, env, .argsK(pending: p.cdr, accumulated: [], env: env, kont))
        default:
            return .returning(expr, kont)
        }
    }

    private func specialForm(_ base: String, _ expr: Value, _ env: Environment, _ kont: Kont) throws -> MachineState? {
        switch base {
        case "quote":
            return .returning(try cadrOf(expr), kont)
        case "quasiquote":
            return .evaluating(expandQuasi(try cadrOf(expr), 1), env, kont)
        case "if":
            let parts = try listToArray(expr)
            guard parts.count >= 3 else { throw schemeError("malformed if") }
            let els = parts.count > 3 ? parts[3] : nil
            return .evaluating(parts[1], env, .ifK(then: parts[2], els: els, env: env, kont))
        case "define":
            return try evalDefine(expr, env, kont)
        case "set!":
            let parts = try listToArray(expr)
            guard parts.count == 3, case .symbol(let name) = parts[1] else {
                throw schemeError("malformed set!")
            }
            return .evaluating(parts[2], env, .setK(name: name, env: env, kont))
        case "lambda":
            let parts = try listToArray(expr)
            guard parts.count >= 2 else { throw schemeError("malformed lambda") }
            let closure = try makeClosure(parts[1], Array(parts[2...]), env, "lambda")
            return .returning(closure, kont)
        case "begin":
            let parts = try listToArray(expr)
            return seqState(Array(parts[1...]), env, kont)
        case "let":
            return .evaluating(try desugarLet(expr, gensym), env, kont)
        case "let*":
            return .evaluating(try desugarLetStar(expr), env, kont)
        case "letrec", "letrec*":
            return .evaluating(try desugarLetrec(expr), env, kont)
        case "cond":
            return .evaluating(try desugarCond(expr, gensym), env, kont)
        case "case":
            return .evaluating(try desugarCase(expr, gensym), env, kont)
        case "and":
            return .evaluating(try desugarAnd(expr), env, kont)
        case "or":
            return .evaluating(try desugarOr(expr, gensym), env, kont)
        case "define-syntax":
            let parts = try listToArray(expr)
            guard parts.count == 3, case .symbol(let name) = parts[1] else {
                throw schemeError("malformed define-syntax")
            }
            let rules = try SyntaxRules.parse(parts[2])
            env.define(name, .syntax(rules))
            return .returning(.unspecified, kont)
        case "let-syntax", "letrec-syntax":
            let parts = try listToArray(expr)
            let bindings = try listToArray(parts[1])
            let child = Environment(parent: env)
            for b in bindings {
                let bp = try listToArray(b)
                guard case .symbol(let name) = bp[0] else { throw schemeError("bad let-syntax binding") }
                child.define(name, .syntax(try SyntaxRules.parse(bp[1])))
            }
            return seqState(Array(parts[2...]), child, kont)
        default:
            return nil
        }
    }

    private func evalDefine(_ expr: Value, _ env: Environment, _ kont: Kont) throws -> MachineState {
        let parts = try listToArray(expr)
        guard parts.count >= 2 else { throw schemeError("malformed define") }
        switch parts[1] {
        case .symbol(let name):
            let valueExpr = parts.count > 2 ? parts[2] : .unspecified
            return .evaluating(valueExpr, env, .defineK(name: name, env: env, kont))
        case .pair(let header):
            guard case .symbol(let name) = header.car else { throw schemeError("bad define header") }
            let lambdaExpr = arrayToList([sym("lambda"), header.cdr] + Array(parts[2...]))
            return .evaluating(lambdaExpr, env, .defineK(name: name, env: env, kont))
        default:
            throw schemeError("malformed define")
        }
    }

    private func apply(_ proc: Value, _ args: [Value], _ kont: Kont) throws -> MachineState {
        switch proc {
        case .continuation(let saved):
            return .returning(args.first ?? .unspecified, saved)
        case .builtin(let builtin):
            switch builtin.special {
            case .callCC:
                guard args.count == 1 else {
                    throw schemeError("call/cc expects 1 argument")
                }
                let continuation = Value.continuation(kont)
                return .applying(args[0], [continuation], kont)
            case .apply:
                guard args.count >= 2 else {
                    throw schemeError("apply expects at least 2 arguments")
                }
                let target = args[0]
                let middle = Array(args[1..<(args.count - 1)])
                let tail = try listToArray(args[args.count - 1])
                return .applying(target, middle + tail, kont)
            case .none:
                let value = try builtin.fn(args)
                return .returning(value, kont)
            }
        case .closure(let lam):
            let newEnv = try bindArguments(lam, args)
            return seqState(lam.body, newEnv, kont)
        default:
            throw schemeError("not a procedure", [proc])
        }
    }

    private func bindArguments(_ lam: Lambda, _ args: [Value]) throws -> Environment {
        let newEnv = Environment(parent: lam.env)
        if lam.rest == nil {
            guard args.count == lam.params.count else {
                throw schemeError("\(lam.name): expected \(lam.params.count) arguments, got \(args.count)")
            }
        } else {
            guard args.count >= lam.params.count else {
                throw schemeError("\(lam.name): expected at least \(lam.params.count) arguments, got \(args.count)")
            }
        }
        for (i, p) in lam.params.enumerated() {
            newEnv.define(p, args[i])
        }
        if let rest = lam.rest {
            newEnv.define(rest, arrayToList(Array(args[lam.params.count...])))
        }
        return newEnv
    }

    private func seqState(_ exprs: [Value], _ env: Environment, _ kont: Kont) -> MachineState {
        if exprs.isEmpty { return .returning(.unspecified, kont) }
        if exprs.count == 1 { return .evaluating(exprs[0], env, kont) }
        return .evaluating(exprs[0], env, .seqK(remaining: Array(exprs[1...]), env: env, kont))
    }
}

func makeClosure(_ formals: Value, _ body: [Value], _ env: Environment, _ name: String) throws -> Value {
    if case .symbol(let rest) = formals {
        return .closure(Lambda(params: [], rest: rest, body: body, env: env, name: name))
    }
    let (elems, tail) = listToArrayWithTail(formals)
    var params: [String] = []
    for e in elems {
        guard case .symbol(let p) = e else { throw schemeError("bad lambda formal") }
        params.append(p)
    }
    var rest: String? = nil
    if case .symbol(let r) = tail {
        rest = r
    } else if case .null = tail {
        rest = nil
    } else {
        throw schemeError("bad lambda formals")
    }
    return .closure(Lambda(params: params, rest: rest, body: body, env: env, name: name))
}
