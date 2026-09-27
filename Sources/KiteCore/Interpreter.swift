public final class Interpreter {
    public let globalEnv: Environment
    let gensym: Gensym
    public var output: (String) -> Void
    private var winderCounter = 0

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

    private func loadPrelude() {
        let preludeEnv = Environment(parent: globalEnv)
        installPreludeInternals(BuiltinRegistry(env: preludeEnv))
        do {
            for form in try Reader(preludeSource).readProgram() {
                _ = try run(.evaluating(form, preludeEnv, .done))
            }
        } catch {
            fatalError("prelude failed to load: \(error)")
        }
        for (name, value) in preludeEnv.vars where !name.hasPrefix("%") {
            globalEnv.define(name, value)
        }
    }

    private func nextWinderId() -> Int {
        winderCounter += 1
        return winderCounter
    }

    private func run(_ initial: MachineState) throws -> Value {
        var state = initial
        var winders: [Winder] = []
        var handlers: [Value] = []
        while true {
            do {
                switch state {
                case .returning(let value, let kont):
                    if case .done = kont { return value }
                    state = try applyKont(value, kont, &winders, &handlers)
                case .evaluating(let expr, let env, let kont):
                    state = try step(expr, env, kont)
                case .applying(let proc, let args, let kont):
                    state = try apply(proc, args, kont, &winders, &handlers)
                }
            } catch let error as SchemeError {
                if handlers.isEmpty {
                    let pending = winders.reversed()
                    winders.removeAll()
                    for winder in pending {
                        _ = try run(.applying(winder.after, [], .done))
                    }
                    throw error
                }
                state = try raise(error.conditionValue, continuable: false, kontOf(state), &handlers)
            }
        }
    }

    private func applyKont(_ value: Value, _ kont: Kont,
                           _ winders: inout [Winder], _ handlers: inout [Value]) throws -> MachineState {
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
        case .popHandlerK(let next):
            if !handlers.isEmpty { handlers.removeLast() }
            return .returning(value, next)
        case .afterHandlerK(let handler, let continuable, let next):
            if continuable {
                handlers.append(handler)
                return .returning(value, next)
            }
            let secondary = Value.errorObject(ErrorObject(message: "exception handler returned", irritants: [value]))
            return try raise(secondary, continuable: false, next, &handlers)
        case .dwBeforeK(let before, let thunk, let after, let next):
            let id = nextWinderId()
            winders.append(Winder(id: id, before: before, after: after))
            return .applying(thunk, [], .dwThunkK(after: after, winderId: id, next))
        case .dwThunkK(let after, let winderId, let next):
            if let idx = winders.lastIndex(where: { $0.id == winderId }) {
                winders.remove(at: idx)
            }
            return .applying(after, [], .dwAfterK(result: value, next))
        case .dwAfterK(let result, let next):
            return .returning(result, next)
        case .rewindK(let afters, let befores, let target, let arg, let saved):
            if let after = afters.first {
                winders.removeLast()
                return .applying(after, [], .rewindK(afters: Array(afters.dropFirst()), befores: befores,
                                                     target: target, arg: arg, saved: saved))
            }
            if let winder = befores.first {
                return .applying(winder.before, [], .rewindK(afters: [], befores: Array(befores.dropFirst()),
                                                             target: target, arg: arg, saved: saved))
            }
            winders = target
            return .returning(arg, saved)
        case .callValuesK(let receiver, let next):
            if case .values(let vs) = value { return .applying(receiver, vs, next) }
            return .applying(receiver, [value], next)
        }
    }

    private func raise(_ condition: Value, continuable: Bool, _ kont: Kont,
                       _ handlers: inout [Value]) throws -> MachineState {
        guard let handler = handlers.popLast() else { throw conditionError(condition) }
        return .applying(handler, [condition], .afterHandlerK(handler: handler, continuable: continuable, kont))
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
                if let head = env.get(s) {
                    if case .syntax(let rules) = head {
                        return .evaluating(try rules.expand(expr, gensym), env, kont)
                    }
                } else if let special = try specialForm(baseName(s), expr, env, kont) {
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
        case "do":
            return .evaluating(try desugarDo(expr, gensym), env, kont)
        case "let-values":
            return .evaluating(try desugarLetValues(expr, gensym), env, kont)
        case "let*-values":
            return .evaluating(try desugarLetStarValues(expr), env, kont)
        case "define-values":
            return .evaluating(try desugarDefineValues(expr, gensym), env, kont)
        case "define-record-type":
            try defineRecordType(expr, in: env)
            return .returning(.unspecified, kont)
        case "delay", "delay-force":
            let thunk = try makeClosure(.null, [try cadrOf(expr)], env, "promise")
            let promise = Promise(done: false, lazy: base == "delay-force", payload: thunk)
            return .returning(.promise(promise), kont)
        case "define-syntax":
            let parts = try listToArray(expr)
            guard parts.count == 3, case .symbol(let name) = parts[1] else {
                throw schemeError("malformed define-syntax")
            }
            env.define(name, .syntax(try SyntaxRules.parse(parts[2], definedIn: env)))
            return .returning(.unspecified, kont)
        case "let-syntax", "letrec-syntax":
            let parts = try listToArray(expr)
            guard parts.count >= 2 else { throw schemeError("malformed \(base)") }
            let child = Environment(parent: env)
            let definitionEnv = base == "letrec-syntax" ? child : env
            for binding in try listToArray(parts[1]) {
                let bp = try listToArray(binding)
                guard bp.count == 2, case .symbol(let name) = bp[0] else {
                    throw schemeError("bad \(base) binding")
                }
                child.define(name, .syntax(try SyntaxRules.parse(bp[1], definedIn: definitionEnv)))
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
            let lambdaExpr = arrayToList([core("lambda"), header.cdr] + Array(parts[2...]))
            return .evaluating(lambdaExpr, env, .defineK(name: name, env: env, kont))
        default:
            throw schemeError("malformed define")
        }
    }

    private func apply(_ proc: Value, _ args: [Value], _ kont: Kont,
                       _ winders: inout [Winder], _ handlers: inout [Value]) throws -> MachineState {
        switch proc {
        case .continuation(let savedKont, let targetWinders, let savedHandlers):
            let arg: Value = args.count == 1 ? args[0] : .values(args)
            handlers = savedHandlers
            var common = 0
            while common < winders.count, common < targetWinders.count,
                  winders[common].id == targetWinders[common].id {
                common += 1
            }
            let afters = winders[common...].reversed().map { $0.after }
            let befores = Array(targetWinders[common...])
            return .returning(.unspecified, .rewindK(afters: afters, befores: befores,
                                                     target: targetWinders, arg: arg, saved: savedKont))
        case .builtin(let builtin):
            try builtin.arity.check(args.count, builtin.name)
            switch builtin.special {
            case .none:
                return .returning(try builtin.fn(args), kont)
            case .callCC:
                return .applying(args[0], [.continuation(kont, winders, handlers)], kont)
            case .apply:
                let middle = Array(args[1..<(args.count - 1)])
                let tail = try listToArray(args[args.count - 1])
                return .applying(args[0], middle + tail, kont)
            case .values:
                return .returning(args.count == 1 ? args[0] : .values(args), kont)
            case .callWithValues:
                return .applying(args[0], [], .callValuesK(receiver: args[1], kont))
            case .dynamicWind:
                return .applying(args[0], [], .dwBeforeK(before: args[0], thunk: args[1], after: args[2], kont))
            case .withExceptionHandler:
                handlers.append(args[0])
                return .applying(args[1], [], .popHandlerK(kont))
            case .raise:
                return try raise(args[0], continuable: false, kont, &handlers)
            case .raiseContinuable:
                return try raise(args[0], continuable: true, kont, &handlers)
            }
        case .closure(let lam):
            return seqState(lam.body, try bindArguments(lam, args), kont)
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
