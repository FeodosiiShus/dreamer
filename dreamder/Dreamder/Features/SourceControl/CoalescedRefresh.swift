import Foundation

actor CoalescedRefresh {
    private var running: Task<Void, Never>?
    private var requested = false

    func run(_ work: @escaping @Sendable () async -> Void) async {
        requested = true
        if running == nil {
            running = Task { await self.drain(work) }
        }
        await running?.value
    }

    private func drain(_ work: @escaping @Sendable () async -> Void) async {
        while requested {
            requested = false
            await work()
        }
        running = nil
    }
}
