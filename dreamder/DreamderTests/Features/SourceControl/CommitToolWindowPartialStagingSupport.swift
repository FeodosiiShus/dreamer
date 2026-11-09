import Foundation
@testable import Dreamder

nonisolated struct CommitToolWindowRepositoryState: Equatable, Sendable {
    let stagedDiff: String
    let indexEntries: String
    let indexTree: String
    let worktree: [String: Data]

    static func capture(of fixture: GitMergeFixture, files: [String]) async throws -> CommitToolWindowRepositoryState {
        var bytes: [String: Data] = [:]
        for name in files {
            bytes[name] = try? Data(contentsOf: fixture.root.appending(path: name))
        }
        return CommitToolWindowRepositoryState(
            stagedDiff: try await fixture.run("diff", "--cached"),
            indexEntries: try await fixture.run("ls-files", "--stage"),
            indexTree: try await fixture.run("write-tree"),
            worktree: bytes
        )
    }
}

nonisolated enum CommitToolWindowSampleText {
    static func numbered(replacing replacements: [Int: String] = [:], lineEnding: String = "\n") -> String {
        (1...20).map { "\(replacements[$0] ?? "l\($0)")\(lineEnding)" }.joined()
    }

    static func hunkCount(_ fixture: GitMergeFixture, _ arguments: String...) async throws -> Int {
        let output = try await fixture.runAllowingFailure(arguments)
        return PartialCommitDiffParser.hunks(inDiff: output).count
    }
}

nonisolated enum CommitToolWindowLineEndingSetup: String, CaseIterable, Sendable, CustomStringConvertible {
    case attributesEolCrlf
    case autocrlfTrue

    var description: String { rawValue }

    func apply(to fixture: GitMergeFixture) async throws {
        switch self {
        case .attributesEolCrlf:
            try fixture.write(".gitattributes", "* text eol=crlf\n")
        case .autocrlfTrue:
            try await fixture.run("config", "core.autocrlf", "true")
        }
    }
}
