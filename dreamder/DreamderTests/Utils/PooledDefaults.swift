import Foundation

nonisolated final class PooledDefaults {
    let defaults: UserDefaults
    let suiteName: String

    init() throws {
        let created = try makeIsolatedDefaults()
        defaults = created.defaults
        suiteName = created.suiteName
    }

    deinit {
        removeIsolatedDefaults(defaults, suiteName: suiteName)
    }
}

nonisolated final class PooledDefaultsLeases {
    private var held: [PooledDefaults] = []

    func make() throws -> UserDefaults {
        let pooled = try PooledDefaults()
        held.append(pooled)
        return pooled.defaults
    }
}
