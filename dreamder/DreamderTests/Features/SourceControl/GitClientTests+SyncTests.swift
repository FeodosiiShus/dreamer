import Foundation
import Testing
@testable import Dreamder

extension GitClientTests {
    @Test
    func unsyncedCommitCountsComeFromTheUpstream() async throws {
        try await withTempDir { directory in
            let originDirectory = try directory.appending(path: "origin", directoryHint: .isDirectory)
                .createDirectoryReturningSelf()
            let origin = try await makeRepo(originDirectory)
            let cloneDirectory = directory.appending(path: "clone", directoryHint: .isDirectory)
            try await origin.fixture.run(
                "clone",
                "-q",
                origin.fixture.root.path(percentEncoded: false),
                cloneDirectory.path(percentEncoded: false)
            )
            let clone = GitMergeFixture(existing: cloneDirectory)
            try await clone.run("config", "user.email", "clone@dreamder.test")
            try await clone.run("config", "user.name", "Clone")
            try await clone.run("config", "commit.gpgsign", "false")
            try clone.write("local.txt", "l\n")
            try await clone.commit("local one")
            try clone.write("local2.txt", "l\n")
            try await clone.commit("local two")
            try origin.fixture.write("remote.txt", "r\n")
            try await origin.fixture.commit("remote one")
            try await clone.run("fetch", "-q")

            let client = GitClient(directoryURL: cloneDirectory, shellClient: .live())
            let counts = try await client.numberOfUnsyncedCommits()

            #expect(counts.ahead == 2)
            #expect(counts.behind == 1)
            let current = try #require(try await client.getCurrentBranch())
            #expect(current.upstream == "origin/main")
            #expect(current.ahead == 2)
            #expect(current.behind == 1)
        }
    }

    @Test
    func concurrentWritesAreSerializedPerRepository() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let names = (0..<12).map { "file-\($0).txt" }
            for name in names {
                try repo.fixture.write(name, "x\n")
            }

            try await withThrowingTaskGroup(of: Void.self) { group in
                for name in names {
                    let url = directory.appending(path: name)
                    group.addTask { try await repo.client.add([url]) }
                }
                try await group.waitForAll()
            }

            #expect(try await repo.fixture.stagedPaths() == names.sorted())
        }
    }

    @Test
    func readsDuringWritesKeepWorking() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            for index in 0..<6 {
                try repo.fixture.write("f\(index).txt", "x\n")
            }
            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0..<6 {
                    let url = directory.appending(path: "f\(index).txt")
                    group.addTask { try await repo.client.add([url]) }
                    group.addTask { _ = try await repo.client.getStatus() }
                }
                try await group.waitForAll()
            }
            #expect(try await repo.client.getStatus().changedFiles.count == 6)
        }
    }

    @Test
    func cloningStreamsProgressAndProducesAWorkingCopy() async throws {
        try await withTempDir { directory in
            let originDirectory = try directory.appending(path: "origin", directoryHint: .isDirectory)
                .createDirectoryReturningSelf()
            let origin = try await makeRepo(originDirectory)
            let destination = directory.appending(path: "cloned repo", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let client = GitClient(directoryURL: destination, shellClient: .live())

            var steps = 0
            for try await _ in client.cloneRepository(
                remoteUrl: URL(fileURLWithPath: origin.fixture.root.path(percentEncoded: false)),
                localPath: destination
            ) {
                steps += 1
            }

            #expect(steps > 0)
            let gitDirectoryPath = destination.appending(path: ".git").path(percentEncoded: false)
            #expect(FileManager.default.fileExists(atPath: gitDirectoryPath))
            #expect(try String(contentsOf: destination.appending(path: "a.txt"), encoding: .utf8) == "one\n")
        }
    }

    @Test
    func cloningAnUnknownRepositoryFailsWithGitsMessage() async throws {
        try await withTempDir { directory in
            let destination = directory.appending(path: "target", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let client = GitClient(directoryURL: destination, shellClient: .live())
            do {
                for try await _ in client.cloneRepository(
                    remoteUrl: URL(
                        fileURLWithPath: directory.appending(path: "does-not-exist").path(percentEncoded: false)
                    ),
                    localPath: destination
                ) {}
                Issue.record("expected the clone to fail")
            } catch GitClient.GitClientError.outputError(let message) {
                #expect(message.contains("does-not-exist"))
            }
        }
    }
}
