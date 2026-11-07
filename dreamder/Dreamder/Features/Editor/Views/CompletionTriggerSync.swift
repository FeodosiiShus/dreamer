nonisolated struct CompletionTriggerSync: Sendable, Equatable {
    enum Step: Sendable, Equatable {
        case unchanged
        case adopted
        case applyLater
    }

    private(set) var applied: Set<String>
    private(set) var desired: Set<String>
    private(set) var isApplyPending = false

    init(applied: Set<String> = []) {
        self.applied = applied
        self.desired = applied
    }

    mutating func request(_ characters: Set<String>, hasController: Bool) -> Step {
        desired = characters
        guard desired != applied else { return .unchanged }
        guard hasController else {
            applied = desired
            return .adopted
        }
        guard !isApplyPending else { return .unchanged }
        isApplyPending = true
        return .applyLater
    }

    mutating func commit() -> Set<String> {
        applied = desired
        isApplyPending = false
        return applied
    }
}
