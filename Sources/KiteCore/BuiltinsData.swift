func installVectors(_ r: BuiltinRegistry) {
    r.predicate("vector?") { if case .vector = $0 { return true }; return false }
    r.def("vector", .atLeast(0)) { args in .vector(VectorRef(args)) }
    r.def("make-vector", .between(1, 2)) { args in
        let fill = args.count > 1 ? args[1] : .unspecified
        return .vector(VectorRef(Array(repeating: fill, count: try indexArg(args[0], "make-vector"))))
    }
    r.def("vector-length", .exactly(1)) { args in .integer(try vectorArg(args[0], "vector-length").items.count) }
    r.def("vector-ref", .exactly(2)) { args in
        let v = try vectorArg(args[0], "vector-ref")
        let i = try indexArg(args[1], "vector-ref")
        guard i < v.items.count else { throw schemeError("vector-ref: index out of range", [args[1]]) }
        return v.items[i]
    }
    r.def("vector-set!", .exactly(3)) { args in
        let v = try vectorArg(args[0], "vector-set!")
        let i = try indexArg(args[1], "vector-set!")
        guard i < v.items.count else { throw schemeError("vector-set!: index out of range", [args[1]]) }
        v.items[i] = args[2]
        return .unspecified
    }
    r.def("vector->list", .between(1, 3)) { args in
        let v = try vectorArg(args[0], "vector->list")
        return arrayToList(Array(v.items[try rangeArgs(args, from: 1, count: v.items.count, "vector->list")]))
    }
    r.def("list->vector", .exactly(1)) { args in .vector(VectorRef(try listToArray(args[0]))) }
    r.def("vector-copy", .between(1, 3)) { args in
        let v = try vectorArg(args[0], "vector-copy")
        return .vector(VectorRef(Array(v.items[try rangeArgs(args, from: 1, count: v.items.count, "vector-copy")])))
    }
    r.def("vector-fill!", .between(2, 4)) { args in
        let v = try vectorArg(args[0], "vector-fill!")
        for i in try rangeArgs(args, from: 2, count: v.items.count, "vector-fill!") { v.items[i] = args[1] }
        return .unspecified
    }
    r.def("vector-append", .atLeast(0)) { args in
        .vector(VectorRef(try args.flatMap { try vectorArg($0, "vector-append").items }))
    }
}

func installHashTables(_ r: BuiltinRegistry) {
    func kind(from args: [Value], at index: Int, _ who: String) throws -> HashTable.Kind {
        guard args.count > index else { return .equal }
        guard case .builtin(let b) = args[index] else {
            throw schemeError("\(who): equivalence must be eq?, eqv?, equal? or string=?", [args[index]])
        }
        switch b.name {
        case "eq?", "eqv?", "=": return .eqv
        case "equal?", "string=?": return .equal
        default: throw schemeError("\(who): unsupported equivalence", [args[index]])
        }
    }

    r.predicate("hash-table?") { if case .hashTable = $0 { return true }; return false }
    r.def("make-hash-table", .between(0, 1)) { args in
        .hashTable(HashTable(kind: try kind(from: args, at: 0, "make-hash-table")))
    }
    r.def("alist->hash-table", .between(1, 2)) { args in
        let table = HashTable(kind: try kind(from: args, at: 1, "alist->hash-table"))
        for entry in try listToArray(args[0]) {
            let p = try pairArg(entry, "alist->hash-table")
            if table.lookup(p.car) == nil { table.insert(p.car, p.cdr) }
        }
        return .hashTable(table)
    }
    r.def("hash-table-set!", .exactly(3)) { args in
        try hashTableArg(args[0], "hash-table-set!").insert(args[1], args[2])
        return .unspecified
    }
    r.def("hash-table-ref/default", .exactly(3)) { args in
        try hashTableArg(args[0], "hash-table-ref/default").lookup(args[1]) ?? args[2]
    }
    r.def("hash-table-delete!", .exactly(2)) { args in
        try hashTableArg(args[0], "hash-table-delete!").remove(args[1])
        return .unspecified
    }
    for name in ["hash-table-contains?", "hash-table-exists?"] {
        r.def(name, .exactly(2)) { args in .bool(try hashTableArg(args[0], name).lookup(args[1]) != nil) }
    }
    for name in ["hash-table-count", "hash-table-size"] {
        r.def(name, .exactly(1)) { args in .integer(try hashTableArg(args[0], name).count) }
    }
    r.def("hash-table-keys", .exactly(1)) { args in
        arrayToList(try hashTableArg(args[0], "hash-table-keys").entries.map { $0.key })
    }
    r.def("hash-table-values", .exactly(1)) { args in
        arrayToList(try hashTableArg(args[0], "hash-table-values").entries.map { $0.value })
    }
    r.def("hash-table->alist", .exactly(1)) { args in
        arrayToList(try hashTableArg(args[0], "hash-table->alist").entries.map { cons($0.key, $0.value) })
    }
    r.def("hash-table-copy", .exactly(1)) { args in .hashTable(try hashTableArg(args[0], "hash-table-copy").copy()) }
    r.def("hash-table-clear!", .exactly(1)) { args in
        try hashTableArg(args[0], "hash-table-clear!").clear()
        return .unspecified
    }
}

func installPromises(_ r: BuiltinRegistry) {
    r.predicate("promise?") { if case .promise = $0 { return true }; return false }
    r.def("make-promise", .exactly(1)) { args in
        if case .promise = args[0] { return args[0] }
        return .promise(Promise.resolved(args[0]))
    }
}

func installPreludeInternals(_ r: BuiltinRegistry) {
    r.def("%accepts?", .exactly(2)) { args in
        let count = try intArg(args[1], "case-lambda")
        guard case .closure(let lam) = args[0] else { return .bool(true) }
        return .bool(lam.rest == nil ? count == lam.params.count : count >= lam.params.count)
    }
    r.def("%promise-done?", .exactly(1)) { args in .bool(try promiseArg(args[0], "force").state.done) }
    r.def("%promise-lazy?", .exactly(1)) { args in .bool(try promiseArg(args[0], "force").state.lazy) }
    r.def("%promise-payload", .exactly(1)) { args in try promiseArg(args[0], "force").state.payload }
    r.def("%promise-resolve!", .exactly(2)) { args in
        let state = try promiseArg(args[0], "force").state
        state.done = true
        state.lazy = false
        state.payload = args[1]
        return .unspecified
    }
    r.def("%promise-adopt!", .exactly(2)) { args in
        let outer = try promiseArg(args[0], "force")
        let inner = try promiseArg(args[1], "force")
        outer.state.done = inner.state.done
        outer.state.lazy = inner.state.lazy
        outer.state.payload = inner.state.payload
        inner.state = outer.state
        return .unspecified
    }
}
