import Foundation

nonisolated struct EditorConfigFile: Equatable, Sendable {
    nonisolated struct Pair: Equatable, Sendable {
        let key: String
        let value: String
    }

    nonisolated struct Section: Equatable, Sendable {
        let name: String
        var pairs: [Pair]
    }

    var isRoot: Bool
    var sections: [Section]
}
