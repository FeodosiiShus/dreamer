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
    let commitDate: Date
    let refs: [GitLogRef]
    let subject: String
    let message: String

    init(
        hash: String,
        parents: [String],
        authorName: String,
        authorEmail: String,
        date: Date,
        commitDate: Date? = nil,
        refs: [GitLogRef],
        subject: String,
        message: String? = nil
    ) {
        self.hash = hash
        self.parents = parents
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.date = date
        self.commitDate = commitDate ?? date
        self.refs = refs
        self.subject = subject
        self.message = message ?? subject
    }

    var id: String { hash }

    var shortHash: String { String(hash.prefix(8)) }

    var isMerge: Bool { parents.count > 1 }
}
