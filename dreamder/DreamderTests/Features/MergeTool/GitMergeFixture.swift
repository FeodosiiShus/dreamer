import Foundation
@testable import Dreamder

nonisolated struct GitMergeFixture: Sendable {
    enum FixtureError: Error {
        case gitFailed(String, String)
        case missingFile(String)
    }

    let root: URL

    init(root: URL) async throws {
        self.root = root
        try await run("init", "-q", "-b", "main")
        try await run("config", "user.email", "merge@dreamder.test")
        try await run("config", "user.name", "Merge")
        try await run("config", "commit.gpgsign", "false")
    }

    init(existing root: URL) {
        self.root = root
    }

    @discardableResult
    func run(_ arguments: String...) async throws -> String {
        let output = try await runAllowingFailure(arguments)
        return output
    }

    @discardableResult
    func runAllowingFailure(_ arguments: [String]) async throws -> String {
        let git = await GitExecutableLocator.shared.executableURL()
        return try await ProcessSlotPool.shared.withSlot {
            try await execute(arguments, git: git)
        }
    }

    @concurrent
    private func execute(_ arguments: [String], git: URL) async throws -> String {
        let process = Process()
        process.executableURL = git
        process.currentDirectoryURL = root
        process.arguments = arguments
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/local/bin",
            "HOME": root.path,
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_TERMINAL_PROMPT": "0"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw FixtureError.gitFailed(arguments.joined(separator: " "), output)
        }
        return output
    }

    func runIgnoringFailure(_ arguments: String...) async throws -> String {
        do {
            return try await runAllowingFailure(arguments)
        } catch FixtureError.gitFailed(_, let output) {
            return output
        }
    }

    func write(_ relativePath: String, _ text: String) throws {
        let url = root.appending(path: relativePath)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func read(_ relativePath: String) throws -> String {
        let url = root.appending(path: relativePath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw FixtureError.missingFile(relativePath)
        }
        return text
    }

    func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appending(path: relativePath).path(percentEncoded: false))
    }

    func commit(_ message: String) async throws {
        try await run("add", "-A")
        try await run("commit", "-qm", message)
    }

    func status() async throws -> String {
        try await runIgnoringFailure("status", "--porcelain=v2")
    }

    func unmergedPaths() async throws -> [String] {
        try await status()
            .split(separator: "\n")
            .filter { $0.hasPrefix("u ") }
            .compactMap { $0.split(separator: " ").last.map(String.init) }
            .sorted()
    }

    func hasConflictMarkers(_ relativePath: String) -> Bool {
        (try? read(relativePath))?.contains("<<<<<<<") ?? false
    }

    func isFullyStaged(_ relativePath: String) async throws -> Bool {
        let entries = try await run("ls-files", "--stage", "--", relativePath)
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard entries.count == 1, let entry = entries.first else { return false }
        return entry.contains(" 0\t")
    }

    func stagedPaths() async throws -> [String] {
        try await runIgnoringFailure("diff", "--cached", "--name-only")
            .split(separator: "\n")
            .map(String.init)
            .sorted()
    }
}

extension GitMergeFixture {
    static func mergeConflict(in root: URL) async throws -> GitMergeFixture {
        let fixture = try await GitMergeFixture(root: root)
        try fixture.write(
            "app/config.txt",
            "alpha\nbeta\ngamma\ndelta\nepsilon\nzeta\neta\ntheta\niota\nkappa\nlambda\n"
        )
        try fixture.write("docs/notes.txt", "one\ntwo\nthree\n")
        try await fixture.commit("base")
        try await fixture.run("checkout", "-q", "-b", "feature")
        try fixture.write(
            "app/config.txt",
            "alpha\nbeta\ngamma\ndelta\nepsilon\nzeta-feature\neta\ntheta\niota\nkappa\nfeature-added\nlambda\n"
        )
        try fixture.write("docs/notes.txt", "one\nnotes-feature\nthree\n")
        try await fixture.commit("feature changes")
        try await fixture.run("checkout", "-q", "main")
        try fixture.write(
            "app/config.txt",
            "alpha\nbeta-main\ngamma\ndelta\nepsilon\nzeta-main\neta\ntheta\niota\nkappa\nlambda\n"
        )
        try fixture.write("docs/notes.txt", "one\nnotes-main\nthree\n")
        try await fixture.commit("main changes")
        _ = try await fixture.runIgnoringFailure("merge", "feature")
        return fixture
    }

    static func deleteModifyConflict(in root: URL) async throws -> GitMergeFixture {
        let fixture = try await GitMergeFixture(root: root)
        try fixture.write("gone.txt", "keep me\nsecond line\n")
        try fixture.write("stable.txt", "stable\n")
        try await fixture.commit("base")
        try await fixture.run("checkout", "-q", "-b", "feature")
        try fixture.write("gone.txt", "keep me\nmodified by feature\n")
        try await fixture.commit("feature modifies")
        try await fixture.run("checkout", "-q", "main")
        try await fixture.run("rm", "-q", "gone.txt")
        try await fixture.commit("main deletes")
        _ = try await fixture.runIgnoringFailure("merge", "feature")
        return fixture
    }

    static func rebaseConflict(in root: URL) async throws -> GitMergeFixture {
        let fixture = try await GitMergeFixture(root: root)
        try fixture.write("src/main.swift", "line1\nline2\nline3\n")
        try await fixture.commit("base")
        try await fixture.run("checkout", "-q", "-b", "feature")
        try fixture.write("src/main.swift", "line1\nfeature-line\nline3\n")
        try await fixture.commit("feature edit")
        try await fixture.run("checkout", "-q", "main")
        try fixture.write("src/main.swift", "line1\nmain-line\nline3\n")
        try await fixture.commit("main edit")
        try await fixture.run("checkout", "-q", "feature")
        _ = try await fixture.runIgnoringFailure("rebase", "main")
        return fixture
    }

    static func rebaseOntoDetachedCommitConflict(in root: URL) async throws -> GitMergeFixture {
        let fixture = try await GitMergeFixture(root: root)
        try fixture.write("src/main.swift", "line1\nline2\nline3\n")
        try await fixture.commit("base")
        try await fixture.run("checkout", "-q", "-b", "feature")
        try fixture.write("src/main.swift", "line1\nfeature-line\nline3\n")
        try await fixture.commit("feature edit")
        try await fixture.run("checkout", "-q", "main")
        try fixture.write("src/main.swift", "line1\nmain-line\nline3\n")
        try await fixture.commit("main edit")
        let onto = try await fixture.run("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        try fixture.write("src/other.swift", "other\n")
        try await fixture.commit("main tip")
        try await fixture.run("checkout", "-q", "feature")
        _ = try await fixture.runIgnoringFailure("rebase", onto)
        return fixture
    }

    static func cherryPickConflict(in root: URL) async throws -> GitMergeFixture {
        let fixture = try await GitMergeFixture(root: root)
        try fixture.write("src/main.swift", "line1\nline2\nline3\n")
        try await fixture.commit("base")
        try await fixture.run("checkout", "-q", "-b", "feature")
        try fixture.write("src/main.swift", "line1\nfeature-line\nline3\n")
        try await fixture.commit("feature edit")
        try await fixture.run("checkout", "-q", "main")
        try fixture.write("src/main.swift", "line1\nmain-line\nline3\n")
        try await fixture.commit("main edit")
        _ = try await fixture.runIgnoringFailure("cherry-pick", "feature")
        return fixture
    }

    static func bothAddedConflict(in root: URL) async throws -> GitMergeFixture {
        let fixture = try await GitMergeFixture(root: root)
        try fixture.write("base.txt", "base\n")
        try await fixture.commit("base")
        try await fixture.run("checkout", "-q", "-b", "feature")
        try fixture.write("new.txt", "feature version\n")
        try await fixture.commit("feature adds")
        try await fixture.run("checkout", "-q", "main")
        try fixture.write("new.txt", "main version\n")
        try await fixture.commit("main adds")
        _ = try await fixture.runIgnoringFailure("merge", "feature")
        return fixture
    }
}
