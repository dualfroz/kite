public final class Environment {
    var vars: [String: Value]
    let parent: Environment?

    public init(parent: Environment? = nil) {
        self.vars = [:]
        self.parent = parent
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
        let base = baseName(name)
        if base != name { return get(base) }
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
        let base = baseName(name)
        if base != name { return set(base, value) }
        return false
    }
}
