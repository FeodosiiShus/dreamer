import Foundation

enum Limiter {
    private static var debounceTasks: [AnyHashable: Task<Void, Never>] = [:]

    static func debounce(
        id: AnyHashable,
        duration: TimeInterval,
        clock: any Clock<Duration> = ContinuousClock(),
        action: @escaping @MainActor () -> Void
    ) {
        debounceTasks[id]?.cancel()
        let delay = Duration.seconds(duration)
        debounceTasks[id] = Task { @MainActor in
            do {
                try await Task.sleep(for: delay, clock: clock)
                try Task.checkCancellation()
            } catch {
                return
            }
            debounceTasks[id] = nil
            action()
        }
    }
}
