import Foundation
import Testing
@testable import Dreamder

nonisolated struct ShelfRepo: Sendable {
    static let selectedPaths = ["a.txt", "b.txt", "c.txt", "new.txt"]

    let fixture: GitMergeFixture
    let client: GitClient

    static func make(in directory: URL) async throws -> ShelfRepo {
        let fixture = try await GitMergeFixture(root: directory)
        try fixture.write("a.txt", "a\n")
        try fixture.write("b.txt", "b\n")
        try fixture.write("c.txt", "c\n")
        try fixture.write("old.txt", "old\n")
        try fixture.write("docs/guide.md", "guide\n")
        try await fixture.commit("initial")
        return ShelfRepo(fixture: fixture, client: GitClient(directoryURL: directory, shellClient: .live()))
    }

    func makeMixedChanges() async throws {
        try fixture.write("a.txt", "a2\n")
        try fixture.write("b.txt", "b2\n")
        try await fixture.run("add", "b.txt")
        try FileManager.default.removeItem(at: fixture.root.appending(path: "c.txt"))
        try fixture.write("new.txt", "new\n")
        try fixture.write("old.txt", "old2\n")
        try fixture.write("other.txt", "other\n")
    }

    func stashSubjects() async throws -> [String] {
        try await fixture.run("stash", "list", "--format=%gs")
            .split(separator: "\n")
            .map(String.init)
    }

    func stashHashes() async throws -> [String] {
        try await fixture.run("stash", "list", "--format=%H")
            .split(separator: "\n")
            .map(String.init)
    }

    func plainStash(_ file: String, _ text: String, message: String) async throws -> String {
        try fixture.write(file, text)
        try await fixture.run("stash", "push", "--message", message, "--", file)
        return try await stashHashes().first ?? ""
    }
}

func shelfThrownError<Value>(_ body: () async throws -> Value) async -> (any Error)? {
    do {
        _ = try await body()
        return nil
    } catch {
        return error
    }
}
