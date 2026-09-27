import Foundation

func defineRecordType(_ form: Value, in env: Environment) throws {
    let parts = try listToArray(form)
    guard parts.count >= 3, case .symbol(let typeName) = parts[1] else {
        throw schemeError("malformed define-record-type")
    }
    var fieldNames: [String] = []
    var accessors: [(field: Int, getter: String, setter: String?)] = []
    for spec in parts.dropFirst(4) {
        let specParts = try listToArray(spec)
        guard case .symbol(let field)? = specParts.first, specParts.count <= 3 else {
            throw schemeError("define-record-type: bad field spec", [spec])
        }
        guard !fieldNames.contains(field) else {
            throw schemeError("define-record-type: duplicate field \(baseName(field))")
        }
        fieldNames.append(field)
        let names = try specParts.dropFirst().map { part -> String in
            guard case .symbol(let name) = part else { throw schemeError("define-record-type: bad field spec", [spec]) }
            return name
        }
        if let getter = names.first {
            accessors.append((fieldNames.count - 1, getter, names.count > 1 ? names[1] : nil))
        }
    }

    let displayName = baseName(typeName).trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
    let type = RecordType(name: displayName, fields: fieldNames.map(baseName))
    env.define(typeName, .recordType(type))

    func define(_ name: String, _ arity: Arity, _ fn: @escaping ([Value]) throws -> Value) {
        env.define(name, .builtin(Builtin(name: baseName(name), arity: arity, fn: fn)))
    }

    func instance(_ value: Value, _ who: String) throws -> Record {
        guard case .record(let r) = value, r.type === type else {
            throw schemeError("\(who): expected \(displayName) record", [value])
        }
        return r
    }

    switch parts[2] {
    case .bool(false):
        break
    case .symbol(let constructor):
        define(constructor, .exactly(fieldNames.count)) { args in .record(Record(type: type, fields: args)) }
    default:
        let constructorParts = try listToArray(parts[2])
        guard case .symbol(let constructor)? = constructorParts.first else {
            throw schemeError("define-record-type: bad constructor spec", [parts[2]])
        }
        let slots = try constructorParts.dropFirst().map { argument -> Int in
            guard case .symbol(let field) = argument, let slot = fieldNames.firstIndex(of: field) else {
                throw schemeError("define-record-type: constructor argument is not a field", [argument])
            }
            return slot
        }
        define(constructor, .exactly(slots.count)) { args in
            var values = Array(repeating: Value.unspecified, count: fieldNames.count)
            for (slot, value) in zip(slots, args) { values[slot] = value }
            return .record(Record(type: type, fields: values))
        }
    }

    if parts.count > 3, case .symbol(let predicate) = parts[3] {
        define(predicate, .exactly(1)) { args in
            if case .record(let r) = args[0] { return .bool(r.type === type) }
            return .bool(false)
        }
    }

    for accessor in accessors {
        let getterName = baseName(accessor.getter)
        define(accessor.getter, .exactly(1)) { args in try instance(args[0], getterName).fields[accessor.field] }
        if let setter = accessor.setter {
            let setterName = baseName(setter)
            define(setter, .exactly(2)) { args in
                try instance(args[0], setterName).fields[accessor.field] = args[1]
                return .unspecified
            }
        }
    }
}
