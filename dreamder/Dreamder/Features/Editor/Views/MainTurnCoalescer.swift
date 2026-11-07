final class MainTurnCoalescer {
    private let action: () -> Void
    private var isPending = false

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func request() {
        guard !isPending else { return }
        isPending = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isPending = false
            self.action()
        }
    }
}
