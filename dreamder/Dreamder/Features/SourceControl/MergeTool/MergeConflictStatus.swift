import Foundation

enum MergeSideChange: String, Equatable {
    case modified
    case added
    case deleted
    case absent

    var title: String {
        switch self {
        case .modified: return "Modified"
        case .added: return "Added"
        case .deleted: return "Deleted"
        case .absent: return "Absent"
        }
    }

    var isRemoval: Bool {
        self == .deleted || self == .absent
    }
}

enum MergeSideChoice: Equatable {
    case yours
    case theirs
}

struct MergeConflictEntry: Identifiable, Equatable {
    let path: String
    let statusCodes: String
    let ours: MergeSideChange
    let theirs: MergeSideChange

    var id: String { path }

    var fileName: String { (path as NSString).lastPathComponent }

    var directory: String { (path as NSString).deletingLastPathComponent }

    var isBothDeleted: Bool { ours == .deleted && theirs == .deleted }

    func change(for choice: MergeSideChoice, swapsSides: Bool) -> MergeSideChange {
        switch choice {
        case .yours:
            return swapsSides ? theirs : ours
        case .theirs:
            return swapsSides ? ours : theirs
        }
    }
}

enum MergeConflictStatusParser {
    static func parse(_ output: String) -> [MergeConflictEntry] {
        output
            .split(separator: "\u{0}", omittingEmptySubsequences: true)
            .compactMap(parseRecord)
    }

    static func sideChanges(for codes: String) -> (ours: MergeSideChange, theirs: MergeSideChange) {
        switch codes {
        case "DD": return (.deleted, .deleted)
        case "AU": return (.added, .absent)
        case "UD": return (.modified, .deleted)
        case "UA": return (.absent, .added)
        case "DU": return (.deleted, .modified)
        case "AA": return (.added, .added)
        default: return (.modified, .modified)
        }
    }

    private static func parseRecord(_ record: Substring) -> MergeConflictEntry? {
        guard record.hasPrefix("u ") else { return nil }
        let fields = record.dropFirst(2).split(separator: " ", omittingEmptySubsequences: false)
        guard fields.count >= 10 else { return nil }
        let codes = String(fields[0])
        guard codes.count == 2 else { return nil }
        let path = fields[9...].joined(separator: " ")
        guard !path.isEmpty else { return nil }
        let sides = sideChanges(for: codes)
        return MergeConflictEntry(path: path, statusCodes: codes, ours: sides.ours, theirs: sides.theirs)
    }
}
