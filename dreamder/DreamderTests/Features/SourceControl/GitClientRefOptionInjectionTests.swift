import Foundation
import Testing
@testable import Dreamder

@Suite
struct GitClientRefOptionInjectionTests {
    private static func recordingClient() -> (client: GitClient, fake: FakeProcessRunner) {
        ScmFakeGit.client { _ in ScmFakeGit.ok() }
    }

    private static func thrownError(_ body: () async throws -> Void) async -> (any Error)? {
        do {
            try await body()
            return nil
        } catch {
            return error
        }
    }

    @Test(arguments: RefOperations.all, RefOperations.hostileNames)
    func namesStartingWithADashAreRejectedBeforeGitRuns(operation: RefOperation, name: String) async throws {
        let (client, fake) = Self.recordingClient()

        let error = await Self.thrownError { try await operation.run(client, name) }

        let failure = try #require(error as? GitClient.GitClientError)
        #expect(failure.description.hasPrefix("Invalid reference name '"))
        #expect(failure.description.contains(name))
        #expect(failure.description.hasSuffix("': it must not start with '-'"))
        #expect(fake.invocations.isEmpty)
    }

    @Test(arguments: RefOperations.all, RefOperations.spacedNames)
    func refsFollowEndOfOptionsAndStayOneArgumentOnGit244OrNewer(operation: RefOperation, name: String) async throws {
        let (client, fake) = Self.recordingClient()

        try await operation.run(client, name)

        #expect(fake.invocations.map(ScmFakeGit.arguments) == operation.arguments(name))
    }

    @Test(arguments: RefOperations.hostileNames + RefOperations.spacedNames)
    func branchExistenceQualifiesTheNameUnderRefsHeads(name: String) async throws {
        let (client, fake) = Self.recordingClient()

        #expect(try await client.branchOpsBranchExists(name) == false)

        #expect(fake.invocations.map(ScmFakeGit.arguments) == [["rev-parse", "-q", "--verify", "refs/heads/\(name)"]])
    }

    @Test
    func theOffendingNameIsTheFirstDashLedOneInArgumentOrder() async throws {
        let (client, fake) = Self.recordingClient()

        let error = await Self.thrownError { try await client.branchOpsRenameBranch(oldName: "ok", newName: "-new") }

        let failure = try #require(error as? GitClient.GitClientError)
        #expect(failure.description == "Invalid reference name '-new': it must not start with '-'")
        #expect(fake.invocations.isEmpty)
    }

    @Test
    func absentOptionalRefsAreNotChecked() async throws {
        let (client, fake) = Self.recordingClient()

        try await client.branchOpsAddWorktree(path: "-dir", ref: nil)
        try await client.branchOpsSetUpstream(branch: "x", upstream: nil)

        #expect(fake.invocations.map(ScmFakeGit.arguments) == [
            ["worktree", "add", "--end-of-options", "-dir"],
            ["branch", "--unset-upstream", "--end-of-options", "x"]
        ])
    }

    @Test
    func aTagNamedMinusFCannotTurnCheckoutIntoAForcedCheckout() async throws {
        try await withTempDir { directory in
            let fixture = try await GitMergeFixture(root: directory)
            try fixture.write("a.txt", "committed\n")
            try await fixture.commit("initial")
            try await fixture.run("update-ref", "refs/tags/-f", "HEAD")
            try await fixture.run("update-ref", "refs/remotes/origin/-f", "HEAD")
            try fixture.write("a.txt", "unsaved local work\n")
            let client = GitClient(directoryURL: directory, shellClient: .live())

            let revisionError = await Self.thrownError { try await client.branchOpsCheckoutRevision("-f") }
            let remoteError = await Self.thrownError { try await client.branchOpsCheckoutRemote("origin/-f") }

            let revisionFailure = try #require(revisionError as? GitClient.GitClientError)
            let remoteFailure = try #require(remoteError as? GitClient.GitClientError)
            #expect(revisionFailure.description.contains("Invalid reference name '-f'"))
            #expect(remoteFailure.description.contains("Invalid reference name '-f'"))
            #expect(try fixture.read("a.txt") == "unsaved local work\n")
            let branches = try await fixture.run("branch", "--format=%(refname:short)")
            #expect(branches.split(separator: "\n").map(String.init) == ["main"])
            let head = try await fixture.run("rev-parse", "--abbrev-ref", "HEAD")
            #expect(head.trimmingCharacters(in: .whitespacesAndNewlines) == "main")
        }
    }
}
