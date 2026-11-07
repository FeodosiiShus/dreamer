import Foundation
import Testing

nonisolated enum IsolatedDefaults {
    @TaskLocal static var current: UserDefaults?

    static func makeSuiteName() -> String {
        "dreamder.tests.isolated.\(UUID().uuidString)"
    }

    static func require() throws -> UserDefaults {
        guard let current else { throw IsolatedDefaultsError.outsideIsolatedScope }
        return current
    }
}

nonisolated enum IsolatedDefaultsError: Error, Equatable {
    case suiteUnavailable(String)
    case outsideIsolatedScope
}

nonisolated func makeIsolatedDefaults() throws -> (defaults: UserDefaults, suiteName: String) {
    let suiteName = IsolatedDefaults.makeSuiteName()
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw IsolatedDefaultsError.suiteUnavailable(suiteName)
    }
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
}

nonisolated func removeIsolatedDefaults(_ defaults: UserDefaults, suiteName: String) {
    defaults.removePersistentDomain(forName: suiteName)
}

nonisolated func withIsolatedDefaults<T>(_ body: (UserDefaults) async throws -> T) async throws -> T {
    let (defaults, suiteName) = try makeIsolatedDefaults()
    defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
    return try await IsolatedDefaults.$current.withValue(defaults) {
        try await body(defaults)
    }
}

nonisolated func withIsolatedDefaults<T>(_ body: (UserDefaults) throws -> T) throws -> T {
    let (defaults, suiteName) = try makeIsolatedDefaults()
    defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
    return try IsolatedDefaults.$current.withValue(defaults) {
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
