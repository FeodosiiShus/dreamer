import Foundation
import Synchronization
import Testing

nonisolated final class IsolatedDefaultsPool: Sendable {
    private struct State {
        var free: Set<Int> = []
        var inUse: Set<Int> = []
        var created = 0
    }

    private let prefix: String
    private let state = Mutex(State())

    init(prefix: String) {
        self.prefix = prefix
    }

    func acquire() -> String {
        let index = state.withLock { state -> Int in
            let index: Int
            if let reusable = state.free.min() {
                state.free.remove(reusable)
                index = reusable
            } else {
                index = state.created
                state.created += 1
            }
            state.inUse.insert(index)
            return index
        }
        let name = suiteName(for: index)
        wipe(name)
        return name
    }

    func release(_ name: String) {
        guard let index = index(of: name), state.withLock({ $0.inUse.remove(index) != nil }) else { return }
        wipe(name)
        state.withLock { state in
            _ = state.free.insert(index)
        }
    }

    private func wipe(_ name: String) {
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    }

    private func suiteName(for index: Int) -> String {
        "\(prefix)\(index)"
    }

    private func index(of name: String) -> Int? {
        guard name.hasPrefix(prefix) else { return nil }
        return Int(name.dropFirst(prefix.count))
    }
}

nonisolated enum IsolatedDefaults {
    @TaskLocal static var currentSuiteName: String?

    static let pool = IsolatedDefaultsPool(prefix: "dreamder.tests.isolated." + TestShard.suiteFragment)

    static func require() throws -> UserDefaults {
        guard let currentSuiteName else { throw IsolatedDefaultsError.outsideIsolatedScope }
        guard let defaults = UserDefaults(suiteName: currentSuiteName) else {
            throw IsolatedDefaultsError.suiteUnavailable(currentSuiteName)
        }
        return defaults
    }
}

nonisolated enum IsolatedDefaultsError: Error, Equatable {
    case suiteUnavailable(String)
    case outsideIsolatedScope
}

nonisolated func makeIsolatedDefaults() throws -> (defaults: UserDefaults, suiteName: String) {
    let suiteName = IsolatedDefaults.pool.acquire()
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        IsolatedDefaults.pool.release(suiteName)
        throw IsolatedDefaultsError.suiteUnavailable(suiteName)
    }
    return (defaults, suiteName)
}

nonisolated func removeIsolatedDefaults(_ defaults: UserDefaults, suiteName: String) {
    IsolatedDefaults.pool.release(suiteName)
}

nonisolated func withIsolatedDefaults<T>(_ body: (UserDefaults) async throws -> T) async throws -> T {
    let (defaults, suiteName) = try makeIsolatedDefaults()
    defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
    return try await IsolatedDefaults.$currentSuiteName.withValue(suiteName) {
        try await body(defaults)
    }
}

nonisolated func withIsolatedDefaults<T>(_ body: (UserDefaults) throws -> T) throws -> T {
    let (defaults, suiteName) = try makeIsolatedDefaults()
    defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
    return try IsolatedDefaults.$currentSuiteName.withValue(suiteName) {
        try body(defaults)
    }
}

nonisolated struct IsolatedDefaultsTrait: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool { true }

    @concurrent func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
        guard testCase != nil else {
            try await function()
            return
        }
        try await withIsolatedDefaults { _ in
            try await function()
        }
    }
}

extension Trait where Self == IsolatedDefaultsTrait {
    static var isolatedDefaults: Self { IsolatedDefaultsTrait() }
}
