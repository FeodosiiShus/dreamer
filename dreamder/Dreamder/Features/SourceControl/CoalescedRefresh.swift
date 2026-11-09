import Foundation

actor CoalescedRefresh {
    private var running: Task<Void, Never>?
    private var requested = false
    private var urgent = false
    private var pendingDebounce: Duration = .zero
    private var debounceTimer: Task<Void, Never>?
    private(set) var requestCount = 0

    func run(debounce: Duration = .zero, _ work: @escaping @Sendable () async -> Void) async {
        requestCount += 1
        requested = true
        if debounce > .zero {
            if !urgent {
                pendingDebounce = max(pendingDebounce, debounce)
            }
        } else {
            urgent = true
            pendingDebounce = .zero
            debounceTimer?.cancel()
        }
        if running == nil {
            running = Task { await self.drain(work) }
        }
        await running?.value
    }

    private func drain(_ work: @escaping @Sendable () async -> Void) async {
        while requested {
            if pendingDebounce > .zero {
                let duration = pendingDebounce
                let timer = Task<Void, Never> {
                    _ = try? await Task.sleep(for: duration)
                }
                debounceTimer = timer
                await timer.value
                debounceTimer = nil
            }
            pendingDebounce = .zero
            urgent = false
            requested = false
            await work()
        }
        running = nil
    }
}
