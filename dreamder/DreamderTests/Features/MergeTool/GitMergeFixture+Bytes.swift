import Foundation
@testable import Dreamder

extension GitMergeFixture {
    static func latin1Bytes(_ text: String) -> [UInt8] {
        text.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) }
    }

    static func utf8Bytes(_ text: String) -> [UInt8] {
        Array(text.utf8)
    }

    func writeBytes(_ relativePath: String, _ bytes: [UInt8]) throws {
        let url = root.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(bytes).write(to: url, options: .atomic)
    }

    func readBytes(_ relativePath: String) throws -> [UInt8] {
        Array(try Data(contentsOf: root.appending(path: relativePath)))
    }

    func indexMatchesWorktree(_ relativePath: String) async throws -> Bool {
        let staged = try await run("rev-parse", ":\(relativePath)")
        let worktree = try await run("hash-object", relativePath)
        return staged.trimmingCharacters(in: .whitespacesAndNewlines)
            == worktree.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func byteConflict(
        in root: URL,
        path: String,
        base: [UInt8],
        ours: [UInt8],
        theirs: [UInt8]
    ) async throws -> GitMergeFixture {
        let fixture = try await GitMergeFixture(root: root)
        try fixture.writeBytes(path, base)
        try await fixture.commit("base")
        try await fixture.run("checkout", "-q", "-b", "feature")
        try fixture.writeBytes(path, theirs)
        try await fixture.commit("feature")
        try await fixture.run("checkout", "-q", "main")
        try fixture.writeBytes(path, ours)
        try await fixture.commit("main")
        _ = try await fixture.runIgnoringFailure("merge", "feature")
        return fixture
    }

    static func byteRebaseConflict(
        in root: URL,
        path: String,
        base: [UInt8],
        main: [UInt8],
        feature: [UInt8]
    ) async throws -> GitMergeFixture {
        let fixture = try await GitMergeFixture(root: root)
        try fixture.writeBytes(path, base)
        try await fixture.commit("base")
        try await fixture.run("checkout", "-q", "-b", "feature")
        try fixture.writeBytes(path, feature)
        try await fixture.commit("feature")
        try await fixture.run("checkout", "-q", "main")
        try fixture.writeBytes(path, main)
        try await fixture.commit("main")
        try await fixture.run("checkout", "-q", "feature")
        _ = try await fixture.runIgnoringFailure("rebase", "main")
        return fixture
    }
}
