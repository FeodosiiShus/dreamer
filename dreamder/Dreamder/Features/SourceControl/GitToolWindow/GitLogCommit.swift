import Foundation

nonisolated struct GitLogRef: Hashable, Identifiable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case head
        case branch
        case remote
        case tag
    }

    let name: String
    let kind: Kind

    var id: String { "\(kind.rawValue):\(name)" }
}

nonisolated struct GitLogCommit: Identifiable, Hashable, Sendable {
    let hash: String
    let parents: [String]
    let authorName: String
    let authorEmail: String
    let date: Date
    let refs: [GitLogRef]
    let subject: String

    var id: String { hash }

    var shortHash: String { String(hash.prefix(8)) }

    var isMerge: Bool { parents.count > 1 }

    func matches(graphText query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let needle = trimmed.lowercased()
        if subject.lowercased().contains(needle) || authorName.lowercased().contains(needle) {
            return true
        }
        return hash.lowercased().hasPrefix(needle) || shortHash.lowercased().hasPrefix(needle)
    }
}

nonisolated struct GitLogBranchFilter: Hashable, Identifiable, Sendable {
    let ref: String?
    let title: String

    var id: String { ref ?? "HEAD" }

    static let all = GitLogBranchFilter(ref: nil, title: "HEAD")
}
