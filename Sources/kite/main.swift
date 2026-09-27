import Foundation
import KiteCore

func runFile(_ path: String) -> Int32 {
    guard let source = try? String(contentsOfFile: path, encoding: .utf8) else {
        FileHandle.standardError.write(Data("kite: cannot read file: \(path)\n".utf8))
        return 1
    }
    let interp = Interpreter()
    do {
        try interp.evalString(source)
        return 0
    } catch {
        fflush(stdout)
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        return 1
    }
}

func runRepl() {
    let interp = Interpreter()
    print("kite - a Scheme interpreter. Ctrl-D to exit.")
    var buffer = ""
    while true {
        if buffer.isEmpty {
            print("kite> ", terminator: "")
        } else {
            print("...   ", terminator: "")
        }
        guard let line = readLine(strippingNewline: false) else {
            print("")
            break
        }
        buffer += line
        let forms: [Value]
        do {
            forms = try Reader(buffer).readProgram()
        } catch {
            continue
        }
        buffer = ""
        for form in forms {
            do {
                switch try interp.evalTop(form) {
                case .unspecified:
                    break
                case .values(let parts) where parts.isEmpty:
                    break
                case let value:
                    print(writeString(value))
                }
            } catch {
                print("error: \(error)")
            }
        }
    }
}

let arguments = CommandLine.arguments
if arguments.count > 1 {
    exit(runFile(arguments[1]))
} else {
    runRepl()
}
