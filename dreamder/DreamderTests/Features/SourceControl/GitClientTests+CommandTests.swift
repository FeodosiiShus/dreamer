import Foundation
import Testing
@testable import Dreamder

extension GitClientTests {
    @Test
    func realStatusListsStagedModifiedRenamedAndUntrackedFiles() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try repo.fixture.write("keep me.txt", "keep\n")
            try await repo.fixture.commit("second")
            try repo.fixture.write("a.txt", "changed\n")
            try repo.fixture.write("dir/ünï file.txt", "new\n")
            try await repo.fixture.run("mv", "keep me.txt", "moved é.txt")

            let status = try await repo.client.getStatus()

            #expect(relativePaths(status.changedFiles) == ["a.txt", "moved é.txt"])
            let modified = try #require(status.changedFiles.first { $0.fileURL.relativePath == "a.txt" })
            #expect(modified.status == .modified)
            #expect(modified.stagedStatus == GitStatus.none)
            let renamed = try #require(status.changedFiles.first { $0.fileURL.relativePath == "moved é.txt" })
            #expect(renamed.stagedStatus == .renamed)
            #expect(renamed.originalFilename == "keep me.txt")
            #expect(status.untrackedFiles.map(\.fileURL.lastPathComponent) == ["dir"])
            #expect(status.unmergedChanges.isEmpty)
        }
    }

    @Test
    func scopedStatusOnlyListsChangesBelowTheScope() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try repo.fixture.write("sub/inside.txt", "x\n")
            try repo.fixture.write("other/outside.txt", "y\n")
            let scoped = GitClient(directoryURL: directory, shellClient: .live(), scopePath: "sub")

            let status = try await scoped.getStatus()

            #expect(status.untrackedFiles.map(\.fileURL.lastPathComponent) == ["sub"])
            #expect(scoped.scopePathspecArguments == ["--", "sub"])
            #expect(scoped.scopePathspec == " -- 'sub'")
        }
    }

    @Test
    func outsideARepositoryEveryCommandReportsNotAGitRepository() async throws {
        try await withTempDir { directory in
            let client = GitClient(directoryURL: directory, shellClient: .live())
            await #expect(throws: GitClient.GitClientError.notGitRepository) { try await client.run("status") }
            await #expect(throws: GitClient.GitClientError.notGitRepository) { try await client.getStatus() }
            #expect(await client.validate() == false)
        }
    }

    @Test
    func validateRecognizesWorkTrees() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            #expect(await repo.client.validate())
        }
    }

    @Test
    func aMissingWorkingDirectoryIsAnErrorNotACrash() async {
        let client = GitClient(
            directoryURL: URL(fileURLWithPath: "/nonexistent/dreamder-project-directory"),
            shellClient: .live()
        )
        await #expect(throws: GitClient.GitClientError.self) { try await client.run("status") }
        #expect(await client.validate() == false)
    }

    @Test
    func aFailingCommandSurfacesGitsMessage() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            do {
                _ = try await repo.client.run("checkout missing-branch")
                Issue.record("expected the command to fail")
            } catch GitClient.GitClientError.outputError(let message) {
                #expect(message.contains("missing-branch"))
                #expect(!message.hasPrefix("fatal:") && !message.hasPrefix("error:"))
            }
        }
    }

    @Test
    func standardOutputIsReturnedVerbatim() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let output = try await repo.client.run("rev-parse HEAD")
            #expect(output.trimmingCharacters(in: .whitespacesAndNewlines).count == 40)
        }
    }

    @Test
    func runResultReportsExitCodesInsteadOfThrowing() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let result = try await repo.client.runResult("rev-parse -q --verify refs/heads/nope")
            #expect(result.exitCode == 1)
            #expect(!result.success)
            #expect(result.success(ignoring: [1]))
            #expect(result.output.isEmpty)

            #expect(try await repo.client.run("rev-parse -q --verify refs/heads/nope", accepting: [1]).isEmpty)
            await #expect(throws: GitClient.GitClientError.self) {
                try await repo.client.run("rev-parse -q --verify refs/heads/nope")
            }
        }
    }

    @Test
    func runDataReturnsBinaryBlobsUnchanged() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let bytes = Data([0x00, 0xFF, 0xFE, 0x0A, 0x61, 0x00])
            try bytes.write(to: directory.appending(path: "blob.bin"))
            try await repo.fixture.commit("binary")

            #expect(try await repo.client.runData("show HEAD:blob.bin") == bytes)
            let lossy = try await repo.client.run("show HEAD:blob.bin")
            #expect(lossy.contains("\0"))
            await #expect(throws: GitClient.GitClientError.self) {
                try await repo.client.runData("show HEAD:missing.bin")
            }
        }
    }

    @Test
    func commitMessagesNeverReachAShell() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try repo.fixture.write("b.txt", "b\n")
            try await repo.client.add([directory.appending(path: "b.txt")])
            let message = "fix \"quotes\" & 'single' $(touch pwned-subshell) `touch pwned-backtick` back\\slash"
            let details = "second paragraph\nline 3 ${HOME}; touch pwned-semicolon\n\nfourth"

            try await repo.client.commit(message: message, details: details)

            let stored = try await repo.fixture.run("log", "-1", "--format=%B")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(stored == message + "\n\n" + details)
            for marker in ["pwned-subshell", "pwned-backtick", "pwned-semicolon"] {
                #expect(!repo.fixture.exists(marker))
                let strayPath = FileManager.default.currentDirectoryPath + "/" + marker
                #expect(!FileManager.default.fileExists(atPath: strayPath))
            }
        }
    }

    @Test
    func commitWithoutDetailsStoresOnlyTheMessage() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try repo.fixture.write("b.txt", "b\n")
            try await repo.client.add([directory.appending(path: "b.txt")])
            try await repo.client.commit(message: "just a subject", details: "")
            #expect(
                try await repo.fixture.run("log", "-1", "--format=%B")
                    .trimmingCharacters(in: .whitespacesAndNewlines) == "just a subject"
            )
        }
    }

    @Test
    func theCommitToolWindowQuotingIsParsedWithoutExpansion() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let message = "amend \"x\" $(touch pwned-amend) `touch pwned-amend2` \\ end\nsecond line"

            try await repo.client.commitToolWindow(message: message, amend: true)

            let stored = try await repo.fixture.run("log", "-1", "--format=%B")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(stored == message)
            #expect(!repo.fixture.exists("pwned-amend"))
            #expect(!repo.fixture.exists("pwned-amend2"))
        }
    }

    @Test
    func committingNothingIsReportedAsAnError() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            do {
                try await repo.client.commit(message: "empty", details: nil)
                Issue.record("expected the commit to fail")
            } catch GitClient.GitClientError.outputError(let message) {
                #expect(message.contains("nothing to commit"))
            }
        }
    }
}
