func bound<Value>(_ action: @escaping (Value) -> Void, _ value: Value) -> () -> Void {
    { action(value) }
}

func discarding<Value>(_ action: @escaping () -> Void) -> (Value) -> Void {
    { _ in action() }
}

func reading<Input, Output>(
    _ keyPath: KeyPath<Input, Output>,
    into action: @escaping (Output) -> Void
) -> (Input) -> Void {
    { action($0[keyPath: keyPath]) }
}

func reading<Input, First, Second, Result>(
    _ first: KeyPath<Input, First>,
    _ second: KeyPath<Input, Second>,
    into action: @escaping (First, Second) -> Result
) -> (Input) -> Result {
    { action($0[keyPath: first], $0[keyPath: second]) }
}
