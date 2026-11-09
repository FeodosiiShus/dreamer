import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct GitCheckoutBranchCoverage {
    private let recorder = GitCloneCoverageRecorder()

    private func makeClone(in directory: URL, branches: [String]) async throws -> URL {
        let origin = try await GitCloneCoverageOrigin.makeBare(in: directory, branches: branches)
        let clone = directory.appending(path: "clone", directoryHint: .isDirectory)
        try await GitCloneCoverageOrigin.clone(of: origin, into: clone)
        return clone
    }

    private func currentBranch(of clone: URL) async throws -> String {
        let fixture = GitMergeFixture(existing: clone)
        return try await fixture.run("rev-parse", "--abbrev-ref", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func branch(named name: String, in model: GitCheckoutBranchViewModel) throws -> GitBranch {
        try #require(model.branches.first(where: { $0.name == name }))
    }

    @Test
    func loadBranchesKeepsOnlyRemoteBranchesAndSelectsTheFirst() async throws {
        try await withTempDir { directory in
            let clone = try await makeClone(in: directory, branches: ["feature"])
            let model = GitCheckoutBranchViewModel(repoPath: clone)

            await model.loadBranches()

            #expect(model.repoPath == clone)
            #expect(model.branches.map(\.name) == ["origin/feature", "origin/main"])
            #expect(model.branches.allSatisfy { $0.isRemote })
            #expect(model.selectedBranch?.name == "origin/feature")
        }
    }

    @Test
    func reloadingKeepsAnExistingSelection() async throws {
        try await withTempDir { directory in
            let clone = try await makeClone(in: directory, branches: ["feature"])
            let model = GitCheckoutBranchViewModel(repoPath: clone)
            await model.loadBranches()
            model.selectedBranch = try branch(named: "origin/main", in: model)

            await model.loadBranches()

            #expect(model.selectedBranch?.name == "origin/main")
        }
    }

    @Test
    func loadingFromADirectoryThatIsNotARepositoryLeavesTheListEmpty() async throws {
        try await withTempDir { directory in
            let model = GitCheckoutBranchViewModel(repoPath: directory)

            await model.loadBranches()

            #expect(model.branches.isEmpty)
            #expect(model.selectedBranch == nil)
        }
    }

    @Test
    func checkoutWithoutASelectionChangesNothing() async throws {
        try await withTempDir { directory in
            let clone = try await makeClone(in: directory, branches: ["feature"])
            let model = GitCheckoutBranchViewModel(repoPath: clone)

            await model.checkoutBranch()

            #expect(try await currentBranch(of: clone) == "main")
        }
    }

    @Test
    func checkoutOfTheSelectedRemoteBranchSwitchesTheWorkingTree() async throws {
        try await withTempDir { directory in
            let clone = try await makeClone(in: directory, branches: ["feature"])
            let model = GitCheckoutBranchViewModel(repoPath: clone)
            await model.loadBranches()
            model.selectedBranch = try branch(named: "origin/feature", in: model)

            await model.checkoutBranch()

            #expect(try await currentBranch(of: clone) != "main")
            #expect(FileManager.default.fileExists(atPath: clone.appending(path: "feature.txt").path))
        }
    }

    @Test
    func failingCheckoutIsSwallowedAndLeavesTheBranchUntouched() async throws {
        try await withTempDir { directory in
            let clone = try await makeClone(in: directory, branches: [])
            let model = GitCheckoutBranchViewModel(repoPath: clone)
            model.selectedBranch = GitBranch(
                name: "origin/missing",
                longName: "refs/remotes/origin/missing",
                upstream: nil,
                ahead: 0,
                behind: 0
            )

            await model.checkoutBranch()

            #expect(try await currentBranch(of: clone) == "main")
        }
    }

    @Test
    func viewRendersAnEmptyPickerForARepositoryWithoutRemoteBranches() async throws {
        try await withTempDir { directory in
            let model = GitCheckoutBranchViewModel(repoPath: directory)
            let hosted = HostedViewFixture.host(size: NSSize(width: 480, height: 220)) {
                GitCheckoutBranchView(viewModel: model, openDocument: { _ in })
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(500))

            #expect(hosted.renders())
            #expect(model.branches.isEmpty)
        }
    }

    @Test
    func viewListsRemoteBranchesWithoutTheOriginPrefixAndReRendersOnSelection() async throws {
        try await withTempDir { directory in
            let clone = try await makeClone(in: directory, branches: ["feature"])
            let model = GitCheckoutBranchViewModel(repoPath: clone)
            let hosted = HostedViewFixture.host(size: NSSize(width: 480, height: 220)) {
                GitCheckoutBranchView(viewModel: model, openDocument: { _ in })
            }
            defer { hosted.close() }

            try await eventually(timeout: .seconds(60)) { model.branches.count == 2 && model.selectedBranch != nil }
            try await hosted.settle()
            #expect(hosted.renders())
            let first = hosted.snapshot()

            model.selectedBranch = try branch(named: "origin/main", in: model)
            try await hosted.settle()

            #expect(HostedView.pixelsDiffer(first, hosted.snapshot()))
        }
    }

    @Test
    func repositoryPathInitializerBuildsItsOwnViewModelAndLoadsBranches() async throws {
        try await withTempDir { directory in
            let clone = try await makeClone(in: directory, branches: ["feature"])
            let hosted = HostedViewFixture.host(size: NSSize(width: 480, height: 220)) {
                GitCheckoutBranchView(repoLocalPath: clone, openDocument: { _ in })
            }
            defer { hosted.close() }

            try await hosted.settle(.milliseconds(800))

            #expect(hosted.renders())
        }
    }

    @Test
    func checkoutButtonActionChecksOutDismissesAndOpensTheRepository() async throws {
        try await withTempDir { directory in
            let clone = try await makeClone(in: directory, branches: ["feature"])
            let model = GitCheckoutBranchViewModel(repoPath: clone)
            let recorder = recorder
            let view = GitCheckoutBranchView(viewModel: model, openDocument: { recorder.documents.append($0) })
            let hosted = HostedViewFixture.host(size: NSSize(width: 480, height: 220)) { view }
            defer { hosted.close() }
            try await eventually(timeout: .seconds(60)) { model.branches.count == 2 && model.selectedBranch != nil }
            model.selectedBranch = try branch(named: "origin/feature", in: model)

            view.checkout()
            try await eventually(timeout: .seconds(60)) { !recorder.documents.isEmpty }

            #expect(recorder.documents == [clone])
            #expect(FileManager.default.fileExists(atPath: clone.appending(path: "feature.txt").path))
            #expect(try await currentBranch(of: clone) != "main")
        }
    }
}
