public final class Gensym {
    private var counter = 0
    func next() -> Int {
        counter += 1
        return counter
    }
}

indirect enum MatchTree {
    case leaf(Value)
    case seq([MatchTree])
}

let ellipsisName = "..."

public final class SyntaxRules {
    let literals: [String]
    let rules: [(pattern: Value, template: Value)]

    init(literals: [String], rules: [(Value, Value)]) {
        self.literals = literals
        self.rules = rules
    }

    static func parse(_ spec: Value) throws -> SyntaxRules {
        let elems = try listToArray(spec)
        guard elems.count >= 2, case .symbol(let head) = elems[0], baseName(head) == "syntax-rules" else {
            throw schemeError("malformed syntax-rules")
        }
        let literalForms = try listToArray(elems[1])
        var literals: [String] = []
        for lit in literalForms {
            guard case .symbol(let s) = lit else { throw schemeError("syntax-rules literal must be symbol") }
            literals.append(baseName(s))
        }
        var rules: [(Value, Value)] = []
        for ruleForm in elems[2...] {
            let ruleParts = try listToArray(ruleForm)
            guard ruleParts.count >= 2 else { throw schemeError("malformed syntax rule") }
            let pattern = ruleParts[0]
            let template: Value
            if ruleParts.count == 2 {
                template = ruleParts[1]
            } else {
                template = arrayToList([.symbol("begin")] + Array(ruleParts[1...]))
            }
            rules.append((pattern, template))
        }
        return SyntaxRules(literals: literals, rules: rules)
    }

    func expand(_ form: Value, _ gensym: Gensym) throws -> Value {
        let formArgs: Value
        if case .pair(let p) = form { formArgs = p.cdr } else { formArgs = .null }
        for (pattern, template) in rules {
            let patternArgs: Value
            if case .pair(let pp) = pattern { patternArgs = pp.cdr } else { patternArgs = .null }
            if let bindings = matchPattern(patternArgs, formArgs, literals) {
                let vars = patternVarsIn(pattern, literals)
                let markId = gensym.next()
                return try instantiate(template, bindings, markId, vars, false)
            }
        }
        throw schemeError("no matching syntax rule for \(displayString(form))")
    }
}

func patternVarsIn(_ pattern: Value, _ literals: [String]) -> Set<String> {
    var acc = Set<String>()
    func walk(_ v: Value) {
        switch v {
        case .symbol(let s):
            if s == "_" || baseName(s) == ellipsisName { return }
            if literals.contains(baseName(s)) { return }
            acc.insert(s)
        case .pair(let p):
            walk(p.car)
            walk(p.cdr)
        default:
            break
        }
    }
    walk(pattern)
    return acc
}

func matchPattern(_ pattern: Value, _ form: Value, _ literals: [String]) -> [String: MatchTree]? {
    switch pattern {
    case .symbol(let s):
        if s == "_" { return [:] }
        if baseName(s) == ellipsisName { return nil }
        if literals.contains(baseName(s)) {
            if case .symbol(let fs) = form, baseName(fs) == baseName(s) { return [:] }
            return nil
        }
        return [s: .leaf(form)]
    case .null:
        if case .null = form { return [:] }
        return nil
    case .pair:
        let (pElems, pTail) = listToArrayWithTail(pattern)
        let (fElems, fTail) = listToArrayWithTail(form)
        return matchSeq(pElems, pTail, fElems, fTail, literals)
    case .bool, .integer, .rational, .real, .char, .string:
        return equalValues(pattern, form) ? [:] : nil
    default:
        return nil
    }
}

private func ellipsisIndex(_ pElems: [Value]) -> Int? {
    for i in 1..<max(pElems.count, 1) {
        if i < pElems.count, case .symbol(let s) = pElems[i], baseName(s) == ellipsisName {
            return i
        }
    }
    return nil
}

func matchSeq(_ pElems: [Value], _ pTail: Value, _ fElems: [Value], _ fTail: Value, _ literals: [String]) -> [String: MatchTree]? {
    if let e = ellipsisIndex(pElems) {
        let repeated = pElems[e - 1]
        let preCount = e - 1
        let postPatterns = Array(pElems[(e + 1)...])
        let postCount = postPatterns.count
        if fElems.count < preCount + postCount { return nil }
        var bindings: [String: MatchTree] = [:]
        for i in 0..<preCount {
            guard let m = matchPattern(pElems[i], fElems[i], literals) else { return nil }
            bindings.merge(m) { _, new in new }
        }
        let repeatCount = fElems.count - preCount - postCount
        var iterMatches: [[String: MatchTree]] = []
        for j in 0..<repeatCount {
            guard let m = matchPattern(repeated, fElems[preCount + j], literals) else { return nil }
            iterMatches.append(m)
        }
        for v in patternVarsIn(repeated, literals) {
            bindings[v] = .seq(iterMatches.map { $0[v] ?? .leaf(.unspecified) })
        }
        for i in 0..<postCount {
            guard let m = matchPattern(postPatterns[i], fElems[preCount + repeatCount + i], literals) else { return nil }
            bindings.merge(m) { _, new in new }
        }
        guard let mt = matchPattern(pTail, fTail, literals) else { return nil }
        bindings.merge(mt) { _, new in new }
        return bindings
    }
    if fElems.count != pElems.count { return nil }
    var bindings: [String: MatchTree] = [:]
    for i in 0..<pElems.count {
        guard let m = matchPattern(pElems[i], fElems[i], literals) else { return nil }
        bindings.merge(m) { _, new in new }
    }
    guard let mt = matchPattern(pTail, fTail, literals) else { return nil }
    bindings.merge(mt) { _, new in new }
    return bindings
}

func instantiate(_ template: Value, _ bindings: [String: MatchTree], _ markId: Int, _ patternVars: Set<String>, _ inQuote: Bool) throws -> Value {
    switch template {
    case .symbol(let s):
        if patternVars.contains(s) {
            guard case .leaf(let v)? = bindings[s] else {
                throw schemeError("pattern variable used at wrong ellipsis depth: \(baseName(s))")
            }
            return v
        }
        if inQuote { return template }
        if baseName(s) == ellipsisName { return template }
        return .symbol(s + String(hygieneMark) + String(markId))
    case .pair:
        let (elems, tail) = listToArrayWithTail(template)
        if elems.count == 2, case .symbol(let s0) = elems[0], baseName(s0) == "quote", case .null = tail {
            let inner = try instantiate(elems[1], bindings, markId, patternVars, true)
            return arrayToList([.symbol("quote"), inner])
        }
        var out: [Value] = []
        var i = 0
        while i < elems.count {
            if i + 1 < elems.count, case .symbol(let e) = elems[i + 1], baseName(e) == ellipsisName {
                let sub = elems[i]
                let evars = patternVarsIn(sub, []).filter {
                    if case .seq? = bindings[$0] { return true }
                    return false
                }
                let n = try lockstepCount(Array(evars), bindings)
                for j in 0..<n {
                    var child = bindings
                    for v in evars {
                        if case .seq(let arr)? = bindings[v] { child[v] = arr[j] }
                    }
                    out.append(try instantiate(sub, child, markId, patternVars, inQuote))
                }
                i += 2
            } else {
                out.append(try instantiate(elems[i], bindings, markId, patternVars, inQuote))
                i += 1
            }
        }
        let newTail: Value
        if case .null = tail {
            newTail = .null
        } else {
            newTail = try instantiate(tail, bindings, markId, patternVars, inQuote)
        }
        return arrayToList(out, tail: newTail)
    default:
        return template
    }
}

private func lockstepCount(_ evars: [String], _ bindings: [String: MatchTree]) throws -> Int {
    var count: Int? = nil
    for v in evars {
        if case .seq(let arr)? = bindings[v] {
            if let c = count, c != arr.count {
                throw schemeError("mismatched ellipsis counts")
            }
            count = arr.count
        }
    }
    guard let n = count else {
        throw schemeError("ellipsis template with no pattern variables")
    }
    return n
}
