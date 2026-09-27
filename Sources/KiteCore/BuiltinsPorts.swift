func installPorts(_ r: BuiltinRegistry, interp: Interpreter) {
    let console = Port.sinkOutput { [weak interp] text in interp?.output(text) }

    func outputPort(_ args: [Value], at index: Int, _ who: String) throws -> Port {
        args.count > index ? try portArg(args[index], who) : console
    }

    func inputPort(_ args: [Value], _ who: String) throws -> Port {
        guard let first = args.first else { throw schemeError("\(who): no current input port, pass a port") }
        return try portArg(first, who)
    }

    r.def("current-output-port", .exactly(0)) { _ in .port(console) }
    r.def("display", .between(1, 2)) { args in
        try outputPort(args, at: 1, "display").write(displayString(args[0]), "display")
        return .unspecified
    }
    r.def("write", .between(1, 2)) { args in
        try outputPort(args, at: 1, "write").write(writeString(args[0]), "write")
        return .unspecified
    }
    r.def("newline", .between(0, 1)) { args in
        try outputPort(args, at: 0, "newline").write("\n", "newline")
        return .unspecified
    }
    r.def("write-char", .between(1, 2)) { args in
        let c = try charArg(args[0], "write-char")
        try outputPort(args, at: 1, "write-char").write(String(c), "write-char")
        return .unspecified
    }
    r.def("write-string", .between(1, 2)) { args in
        let text = try stringArg(args[0], "write-string")
        try outputPort(args, at: 1, "write-string").write(text, "write-string")
        return .unspecified
    }

    r.def("open-input-string", .exactly(1)) { args in
        .port(Port.inputString(try stringArg(args[0], "open-input-string")))
    }
    r.def("open-output-string", .exactly(0)) { _ in .port(Port.outputString()) }
    r.def("get-output-string", .exactly(1)) { args in
        .string(try portArg(args[0], "get-output-string").outputText())
    }
    r.def("read-char", .between(0, 1)) { args in
        try inputPort(args, "read-char").readChar().map { .char($0) } ?? .eof
    }
    r.def("peek-char", .between(0, 1)) { args in
        try inputPort(args, "peek-char").peekChar().map { .char($0) } ?? .eof
    }
    r.def("read-line", .between(0, 1)) { args in
        try inputPort(args, "read-line").readLine().map { .string($0) } ?? .eof
    }
    r.def("read-string", .between(1, 2)) { args in
        let limit = try indexArg(args[0], "read-string")
        return try inputPort(Array(args.dropFirst()), "read-string").readString(limit).map { .string($0) } ?? .eof
    }
    r.def("char-ready?", .between(0, 1)) { args in .bool(try inputPort(args, "char-ready?").charReady()) }
    r.def("read", .between(0, 1)) { args in
        let port = try inputPort(args, "read")
        do {
            return try port.readDatum()
        } catch let error as SchemeError {
            let condition = ErrorObject(message: "read: " + error.message, irritants: error.irritants, kind: .read)
            throw SchemeError(condition.message, irritants: condition.irritants, condition: .errorObject(condition))
        }
    }

    r.def("eof-object", .exactly(0)) { _ in .eof }
    r.predicate("eof-object?") { if case .eof = $0 { return true }; return false }
    r.predicate("port?") { if case .port = $0 { return true }; return false }
    r.predicate("textual-port?") { if case .port = $0 { return true }; return false }
    r.predicate("input-port?") { if case .port(let p) = $0 { return p.isInput }; return false }
    r.predicate("output-port?") { if case .port(let p) = $0 { return !p.isInput }; return false }
    r.predicate("input-port-open?") { if case .port(let p) = $0 { return p.isInput && p.isOpen }; return false }
    r.predicate("output-port-open?") { if case .port(let p) = $0 { return !p.isInput && p.isOpen }; return false }
    for name in ["close-port", "close-input-port", "close-output-port"] {
        r.def(name, .exactly(1)) { args in
            try portArg(args[0], name).close()
            return .unspecified
        }
    }
}
