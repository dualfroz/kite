let rootScopeMark = "0.0"

final class MacroScopes {
    private var definitionEnvs: [Int: Environment] = [:]
    private var counter = 0

    init(root: Environment) {
        definitionEnvs[0] = root
    }

    func register(_ env: Environment) -> Int {
        counter += 1
        definitionEnvs[counter] = env
        return counter
    }

    func definitionEnv(of name: String) -> (String, Environment)? {
        guard let markStart = name.lastIndex(of: hygieneMark) else { return nil }
        let mark = name[name.index(after: markStart)...]
        guard let dot = mark.firstIndex(of: "."),
              let macroId = Int(mark[mark.index(after: dot)...]),
              let env = definitionEnvs[macroId] else { return nil }
        return (String(name[..<markStart]), env)
    }
}

public final class Environment {
    var vars: [String: Value]
    let parent: Environment?
    private var inheritedScopes: MacroScopes?

    public init(parent: Environment? = nil) {
        self.vars = [:]
        self.parent = parent
        self.inheritedScopes = parent?.scopes
    }

    var scopes: MacroScopes {
        if let existing = inheritedScopes { return existing }
        let created = MacroScopes(root: self)
        inheritedScopes = created
        return created
    }

    func define(_ name: String, _ value: Value) {
        vars[name] = value
    }

    func get(_ name: String) -> Value? {
        var env: Environment? = self
        while let e = env {
            if let v = e.vars[name] { return v }
            env = e.parent
        }
        if case let (outer, definitionEnv)? = scopes.definitionEnv(of: name) {
            return definitionEnv.get(outer)
        }
        return nil
    }

    @discardableResult
    func set(_ name: String, _ value: Value) -> Bool {
        var env: Environment? = self
        while let e = env {
            if e.vars[name] != nil {
                e.vars[name] = value
                return true
            }
            env = e.parent
        }
        if case let (outer, definitionEnv)? = scopes.definitionEnv(of: name) {
            return definitionEnv.set(outer, value)
        }
        return false
    }
}
