import Foundation

nonisolated struct ProblemCaret: Equatable, Sendable {
    let fileURL: URL
    let line: Int
    let column: Int
}

nonisolated enum ProblemsNavigation {
    enum Direction: Sendable {
        case next
        case previous
    }

    static func ordered(_ nodes: [ProblemFileNode]) -> [WorkspaceDiagnostic] {
        nodes.flatMap(\.diagnostics)
    }

    static func target(
        _ direction: Direction,
        in ordered: [WorkspaceDiagnostic],
        from caret: ProblemCaret?
    ) -> WorkspaceDiagnostic? {
        guard !ordered.isEmpty else { return nil }
        guard let caret else {
            return direction == .next ? ordered.first : ordered.last
        }
        let caretFile = caret.fileURL.standardizedFileURL
        let sameFile = ordered.indices.filter { ordered[$0].fileURL.standardizedFileURL == caretFile }
        guard let firstIndex = sameFile.first, let lastIndex = sameFile.last else {
            return direction == .next ? ordered.first : ordered.last
        }
        if let exact = sameFile.first(where: { position(of: ordered[$0]) == (caret.line, caret.column) }) {
            return ordered[wrapped(direction == .next ? exact + 1 : exact - 1, count: ordered.count)]
        }
        let caretPosition = (caret.line, caret.column)
        switch direction {
        case .next:
            let following = sameFile.filter { position(of: ordered[$0]) > caretPosition }
            if let best = following.min(by: { position(of: ordered[$0]) < position(of: ordered[$1]) }) {
                return ordered[best]
            }
            return ordered[wrapped(lastIndex + 1, count: ordered.count)]
        case .previous:
            let preceding = sameFile.filter { position(of: ordered[$0]) < caretPosition }
            if let best = preceding.max(by: { position(of: ordered[$0]) < position(of: ordered[$1]) }) {
                return ordered[best]
            }
            return ordered[wrapped(firstIndex - 1, count: ordered.count)]
        }
    }

    private static func position(of diagnostic: WorkspaceDiagnostic) -> (Int, Int) {
        (diagnostic.startLine, diagnostic.startColumn)
    }

    private static func wrapped(_ index: Int, count: Int) -> Int {
        ((index % count) + count) % count
    }
}

