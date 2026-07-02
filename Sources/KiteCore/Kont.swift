public struct Winder {
    public let id: Int
    public let before: Value
    public let after: Value
}

public indirect enum Kont {
    case done
    case ifK(then: Value, els: Value?, env: Environment, Kont)
    case defineK(name: String, env: Environment, Kont)
    case setK(name: String, env: Environment, Kont)
    case argsK(pending: Value, accumulated: [Value], env: Environment, Kont)
    case seqK(remaining: [Value], env: Environment, Kont)
    case popHandlerK(Kont)
    case afterHandlerK(handler: Value, continuable: Bool, Kont)
    case dwBeforeK(before: Value, thunk: Value, after: Value, Kont)
    case dwThunkK(after: Value, winderId: Int, Kont)
    case dwAfterK(result: Value, Kont)
    case rewindK(afters: [Value], befores: [Value], target: [Winder], arg: Value, saved: Kont)
    case callValuesK(receiver: Value, Kont)
}

enum MachineState {
    case evaluating(Value, Environment, Kont)
    case returning(Value, Kont)
    case applying(Value, [Value], Kont)
}

func kontOf(_ state: MachineState) -> Kont {
    switch state {
    case .evaluating(_, _, let k): return k
    case .returning(_, let k): return k
    case .applying(_, _, let k): return k
    }
}
