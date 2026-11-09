import Foundation
import Testing
@testable import Dreamder

extension GitClientBranchOperationsCoverage {
    @Test
    func mergeReportsConflictsFromOutputOrStateAndFailuresOtherwise() async throws {
        let (conflicting, _) = ScmFakeGit.client { invocation in
            ScmFakeGit.arguments(invocation).contains("merge")
                ? ScmFakeGit.failure("CONFLICT (content): Merge conflict in a.txt", code: 1)
                : ScmFakeGit.ok()
        }
        #expect(try await conflicting.branchOpsMerge("topic"))

        let (clean, cleanFake) = ScmFakeGit.client { _ in ScmFakeGit.ok() }
        #expect(try await clean.branchOpsMerge("topic") == false)
        #expect(Self.calls(cleanFake).first == [
            "-c", "core.editor=true", "merge", "--no-edit", "--end-of-options", "topic"
        ])

        let (failing, _) = ScmFakeGit.client { _ in ScmFakeGit.failure("fatal: refusing", code: 128) }
        await #expect(throws: GitClient.GitClientError.outputError("refusing")) {
            _ = try await failing.branchOpsMerge("topic")
        }
    }

    @Test
    func rebaseReportsConflictsFromOutputAndFailuresOtherwise() async throws {
        let (conflicting, _) = ScmFakeGit.client { invocation in
            ScmFakeGit.arguments(invocation).first == "rebase"
                ? ScmFakeGit.failure("error: could not apply abc123... change", code: 1)
                : ScmFakeGit.ok()
        }
        #expect(try await conflicting.branchOpsRebase(onto: "main"))

        let (conflictText, _) = ScmFakeGit.client { invocation in
            ScmFakeGit.arguments(invocation).first == "rebase"
                ? FakeProcessRunner.output("CONFLICT (content)", exitCode: 1)
                : ScmFakeGit.ok()
        }
        #expect(try await conflictText.branchOpsRebase(onto: "main"))

        let (clean, _) = ScmFakeGit.client { _ in ScmFakeGit.ok() }
        #expect(try await clean.branchOpsRebase(onto: "main") == false)

        let (failing, _) = ScmFakeGit.client { _ in ScmFakeGit.failure("fatal: invalid upstream", code: 128) }
        await #expect(throws: GitClient.GitClientError.outputError("invalid upstream")) {
            _ = try await failing.branchOpsRebase(onto: "main")
        }
    }

    @Test
    func checkoutAndRebaseSwitchesBeforeReplaying() async throws {
        let (client, fake) = ScmFakeGit.client { _ in ScmFakeGit.ok() }
        #expect(try await client.branchOpsCheckoutAndRebase("feat", onto: "main") == false)
        #expect(Self.calls(fake).prefix(2) == [
            ["checkout", "--end-of-options", "feat"],
            ["rebase", "--end-of-options", "main"]
        ])
    }

    @Test
    func tagsAreParsedFromRefListing() async throws {
        let (client, fake) = ScmFakeGit.client { _ in ScmFakeGit.ok("v2|bbb\nv1|aaa\n\n") }
        let tags = try await client.branchOpsListTags()
        #expect(tags == [GitTag(name: "v1", objectName: "aaa"), GitTag(name: "v2", objectName: "bbb")])
        #expect(Self.calls(fake) == [["for-each-ref", "--format=%(refname:short)|%(objectname:short)", "refs/tags"]])
    }

    @Test
    func revisionsAreTrimmed() async throws {
        let (client, _) = ScmFakeGit.client { _ in ScmFakeGit.ok("abc123\n") }
        #expect(try await client.branchOpsRevision("HEAD") == "abc123")
    }

    @Test
    func recentBranchesFilterTheReflogByExistingLocalBranches() async throws {
        let (client, _) = ScmFakeGit.client { invocation in
            switch ScmFakeGit.arguments(invocation).first {
            case "reflog":
                ScmFakeGit.ok("checkout: moving from main to feature\ncheckout: moving from feature to gone\n")
            default:
                ScmFakeGit.ok("refs/heads/main\nrefs/heads/feature\n")
            }
        }
        let recent = try await client.branchOpsRecentBranchNames(limit: 5)
        #expect(recent == ["feature"])
    }
}
