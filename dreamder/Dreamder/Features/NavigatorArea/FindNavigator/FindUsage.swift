import Foundation

nonisolated struct FindTextPosition: Sendable, Equatable {
    let line: Int
    let column: Int
}

nonisolated struct FindLineIndex: Sendable {
    private let starts: [Int]

    init(_ text: String) {
        var starts = [0]
        var offset = 0
        for unit in text.utf16 {
            offset += 1
            if unit == Self.lineFeed {
                starts.append(offset)
            }
        }
        self.starts = starts
    }

    func position(of offset: Int) -> FindTextPosition {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= offset {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return FindTextPosition(line: low + 1, column: offset - starts[low] + 1)
    }

    private static let lineFeed: UInt16 = 0x0A
}

nonisolated struct FindUsage: Sendable, Equatable {
    let range: NSRange
    let replacement: String?
    let start: FindTextPosition
    let end: FindTextPosition

    static func make(
        for match: NSTextCheckingResult,
        in text: NSString,
        lines: FindLineIndex,
        model: FindModel,
        regex: NSRegularExpression,
        withReplacement: Bool
    ) -> FindUsage {
        let replacement = withReplacement ? (try? model.replacement(for: match, in: text, using: regex)) : nil
        return FindUsage(
            range: match.range,
            replacement: replacement,
            start: lines.position(of: match.range.location),
            end: lines.position(of: NSMaxRange(match.range))
        )
    }

    func moved(by delta: Int, lines: FindLineIndex) -> FindUsage {
        let moved = NSRange(location: range.location + delta, length: range.length)
        return FindUsage(
            range: moved,
            replacement: replacement,
            start: lines.position(of: moved.location),
            end: lines.position(of: NSMaxRange(moved))
        )
    }
}

nonisolated enum FindFileReader {
    static let sniffLength = 8192

    static func text(at url: URL) -> String? {
        if WorkspaceFileScope.binaryExtensions.contains(url.pathExtension.lowercased()) {
            return nil
        }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.count <= WorkspaceFileScope.maxIndexableTextSize,
              !data.prefix(sniffLength).contains(0) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

nonisolated struct FileEvaluation: Sendable {
    nonisolated struct Hit: Sendable {
        let snapshot: FileMatchSnapshot
        let usage: FindUsage
    }

    let hits: [Hit]

    static let empty = FileEvaluation(hits: [])
}

nonisolated struct FileHit: Sendable {
    let url: URL
    let score: Float
    let evaluation: FileEvaluation
}

nonisolated struct FileCandidate: Sendable {
    let url: URL
    let score: Float
}

nonisolated struct FindPlan: Sendable {
    let model: FindModel
    let regex: NSRegularExpression
    let files: [FileCandidate]
    let replacementIssue: String?
    let evaluate: @Sendable (URL) async -> FileEvaluation
}

nonisolated enum FindFailure: Error, Equatable, Sendable {
    case noProject
    case invalidRegularExpression
    case invalidFileMask
    case invalidReplacement(String)

    var message: String {
        switch self {
        case .noProject: "No project is open."
        case .invalidRegularExpression: "Invalid regular expression."
        case .invalidFileMask: "Invalid file mask."
        case .invalidReplacement(let detail): "Invalid replacement string: \(detail)"
        }
    }
}
