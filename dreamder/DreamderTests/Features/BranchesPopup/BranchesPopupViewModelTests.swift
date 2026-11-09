import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct BranchesPopupViewModelTests {
    private final class Registry {
        var harnesses: [Harness] = []
    }

    private let pooledDefaults: PooledDefaults
    private var defaults: UserDefaults { pooledDefaults.defaults }
    private let registry = Registry()

    init() throws {
        pooledDefaults = try PooledDefaults()
    }

    @MainActor
    private final class Harness {
        let fixture: GitMergeFixture
        let manager: SourceControlManager
        let workspace: WorkspaceDocument
        let model: BranchesPopupViewModel
        var dismissals = 0
        var notifications: [BranchesPopupNotificationRequest] = []
        var presentedRefs: [BranchesPopupRow] = []
        var compares: [(branch: String, current: String)] = []
        var conflictsOpened = 0
        var errors: [String] = []

        init(_ fixture: GitMergeFixture, defaults: UserDefaults) {
            self.fixture = fixture
            let dir = fixture.root

            manager = SourceControlManager(workspaceURL: dir, editorManager: EditorManager())
            workspace = WorkspaceDocument()
            workspace.sourceControlManager = manager
            var dismiss: () -> Void = {}
            model = BranchesPopupViewModel(
                sourceControlManager: manager,
                workspace: workspace,
                defaults: defaults,
                dismiss: { dismiss() }
            )
            dismiss = { [weak self] in self?.dismissals += 1 }
            model.dialogs = BranchesPopupDialogs(
                branchDialog: { _ in nil },
                confirm: { _, _, _ in false },
                unmergedDelete: { _, _ in .cancel },
                checkoutRemoteName: { _, _ in nil },
                checkoutRemoteLocalCommits: { _, _, _ in .cancel },
                worktreePath: { _ in nil },
                error: { [weak self] title, _ in self?.errors.append(title) }
            )
            model.notify = { [weak self] request in self?.notifications.append(request) }
            model.presentRefActions = { [weak self] row in self?.presentedRefs.append(row) }
            model.comparePresenter = { [weak self] _, branch, current in
                self?.compares.append((branch, current))
            }
            model.openConflicts = { [weak self] in self?.conflictsOpened += 1 }
        }

        func refRow(_ kind: BranchesPopupRef.Kind, _ shortName: String) -> BranchesPopupRow? {
            model.rows.first { $0.ref?.kind == kind && $0.ref?.shortName == shortName }
        }

        func anyRow(_ shortName: String) -> BranchesPopupRow? {
            model.rows.first { $0.ref?.shortName == shortName }
        }

        func branches() async throws -> [String] {
            try await fixture.run("branch", "--format=%(refname:short)")
                .split(separator: "\n")
                .map(String.init)
                .sorted()
        }

        func upstream(of branch: String) async -> String? {
            let output = try? await fixture.run("rev-parse", "--abbrev-ref", "\(branch)@{upstream}")
            let value = output?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == true ? nil : value
        }
    }

    private func withTempDir(_ test: (URL) async throws -> Void) async throws {
        try await DreamderTests.withTempDir { dir in
            defer { registry.harnesses.removeAll() }
            try await test(dir)
            try await eventually { registry.harnesses.allSatisfy { $0.model.runningOperations == 0 } }
        }
    }

    private func loaded(_ dir: URL, existing: Bool = false) async throws -> Harness {
        let fixture: GitMergeFixture
        if existing {
            fixture = GitMergeFixture(existing: dir)
        } else {
            try await BranchesPopupTemplateRepository.local.copy(into: dir)
            fixture = GitMergeFixture(existing: dir)
        }
        let harness = Harness(fixture, defaults: defaults)
        registry.harnesses.append(harness)
        await harness.model.reload()
        try await eventually {
            harness.model.isLoading == false && harness.model.rows.contains { $0.ref != nil }
        }
        return harness
    }

    @Test
    func reloadListsBranchesAndTagsAndSelectsThePreviousBranch() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            let model = harness.model

            #expect(model.currentBranchName == "main")
            #expect(model.selectedRow?.ref?.shortName == "feature")
            #expect(model.selectedRow?.ref?.isCurrent == false)
            for name in ["main", "feature", "obsolete"] {
                #expect(harness.anyRow(name) != nil)
            }
            #expect(harness.refRow(.tag, "v1.0") == nil)
            model.toggleExpansion(.section(.tags))
            #expect(harness.refRow(.tag, "v1.0") != nil)
            #expect(model.sections.map(\.id).contains(.tags))
            #expect(model.visibleActions == BranchesPopupActionID.allCases)
            #expect(model.emptyMessage == nil)
            #expect(model.remoteBranchRefs.isEmpty)
            #expect(model.preferredHeight >= 260 && model.preferredHeight <= 560)
            #expect(model.groupsByDirectory)
        }
    }

    @Test
    func typingFiltersActionsAndSelectsTheBestMatchingBranch() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            let model = harness.model

            model.query = "feat"
            #expect(model.selectedRow?.ref?.shortName == "feature")

            model.query = "push"
            #expect(model.visibleActions == [.push])
            #expect(model.selectedRow?.action == .push)

            model.query = "zzzz-no-branch"
            #expect(model.emptyMessage == "Nothing found")
            #expect(model.visibleActions.isEmpty)
        }
    }

    @Test
    func recentSectionIsCappedAtFiveAndSkipsDeletedBranches() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            for number in 1...7 {
                try await harness.fixture.run("branch", "b\(number)")
                try await harness.fixture.run("checkout", "-q", "b\(number)")
            }
            try await harness.fixture.run("checkout", "-q", "main")
            try await harness.fixture.run("branch", "-D", "b6")
            await harness.model.reload()

            let recent = try #require(harness.model.sections.first { $0.id == .recent })
            let recentNames: [String] = recent.refs.map(\.shortName)
            #expect(recentNames == ["main", "b7", "b5", "b4", "b3"])
            let localRefs: [BranchesPopupRef] = harness.model.sections.first { $0.id == .local }?.refs ?? []
            let mainCount = localRefs.filter { $0.shortName == "main" }.count
            #expect(mainCount == 1)
            #expect(recentNames.filter { $0 == "main" }.count == 1)
        }
    }

    @Test
    func arrowKeysWrapAroundSelectableRows() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            let model = harness.model
            let selectable = model.rows.filter(\.isSelectable)
            model.selectedID = selectable.first?.id

            model.moveSelection(-1)
            #expect(model.selectedID == selectable.last?.id)
            model.moveSelection(1)
            #expect(model.selectedID == selectable.first?.id)

            model.selectedID = nil
            model.moveSelection(1)
            #expect(model.selectedID == selectable.first?.id)
        }
    }

    @Test
    func sectionsCollapseNormallyAndWhileSearching() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            let model = harness.model
            let localSection = BranchesPopupItemID.section(.local)
            #expect(model.isExpanded(localSection))

            let sectionRow = try #require(model.rows.first { $0.id == localSection })
            model.activate(sectionRow)
            #expect(model.isExpanded(localSection) == false)
            #expect(model.rows.contains { $0.id == .ref(.local, "obsolete") } == false)

            model.query = "obsolete"
            #expect(model.isExpanded(localSection))
            model.toggleExpansion(localSection)
            #expect(model.isExpanded(localSection) == false)
            #expect(model.collapsedWhileSearching.contains(localSection))

            model.query = ""
            #expect(model.isExpanded(localSection) == false)
            model.toggleExpansion(localSection)
            #expect(model.isExpanded(localSection))
        }
    }

    @Test
    func activatingABranchOpensItsActionListInsteadOfCheckingOut() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            let row = try #require(harness.anyRow("feature"))

            harness.model.activate(row)

            #expect(harness.presentedRefs.map(\.id) == [row.id])
            #expect(harness.dismissals == 0)
            #expect(harness.manager.currentBranch?.name == "main")
        }
    }

    @Test
    func checkingOutATagDetachesHead() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            harness.model.toggleExpansion(.section(.tags))
            let tag = try #require(harness.refRow(.tag, "v1.0")?.ref)

            harness.model.checkout(tag)

            try await eventually {
                (try? await harness.fixture.run("rev-parse", "--abbrev-ref", "HEAD"))?.hasPrefix("HEAD") == true
            }
        }
    }

    @Test
    func mergeAndRebaseBringFeatureCommitsIntoMain() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            let feature = try #require(harness.anyRow("feature")?.ref)

            harness.model.merge(feature)
            try await eventually { harness.fixture.exists("feature.txt") }

            try await harness.fixture.run("reset", "-q", "--hard", "HEAD~1")
            #expect(harness.fixture.exists("feature.txt") == false)
            harness.model.rebaseCurrent(onto: feature)
            try await eventually { harness.fixture.exists("feature.txt") }
            #expect(try await harness.fixture.run("rev-parse", "--abbrev-ref", "HEAD").hasPrefix("main"))
        }
    }

    @Test
    func checkoutAndRebaseReplaysTheBranchOnCurrent() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            try harness.fixture.write("main.txt", "main\n")
            try await harness.fixture.commit("main work")
            let feature = try #require(harness.anyRow("feature")?.ref)

            harness.model.checkoutAndRebase(feature)

            #expect(harness.dismissals == 1)
            try await eventually { harness.manager.currentBranch?.name == "feature" && harness.fixture.exists("main.txt") }
        }
    }

    @Test
    func mergeConflictsLeaveTheRepositoryMergingAndNotify() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            try await harness.fixture.run("checkout", "-q", "feature")
            try harness.fixture.write("a.txt", "feature side\n")
            try await harness.fixture.commit("feature edits a")
            try await harness.fixture.run("checkout", "-q", "main")
            try harness.fixture.write("a.txt", "main side\n")
            try await harness.fixture.commit("main edits a")
            await harness.model.reload()
            let feature = try #require(harness.anyRow("feature")?.ref)

            harness.model.merge(feature)

            try await eventually {
                harness.model.operationState.isMerging
                    && harness.notifications.contains { $0.title == "Branch 'feature' merged with conflicts" }
            }
            #expect(harness.model.rows.contains { $0.ongoingAction == .mergeAbort })

            harness.notifications.last?.action()
            #expect(harness.conflictsOpened == 1)
            try await harness.fixture.run("merge", "--abort")
            await harness.model.reload()
            #expect(harness.model.operationState == .none)
        }
    }

    @Test
    func ongoingRebaseActionsAreListedAndAbortWorks() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            try await harness.fixture.run("checkout", "-q", "feature")
            try harness.fixture.write("a.txt", "feature side\n")
            try await harness.fixture.commit("feature edits a")
            try await harness.fixture.run("checkout", "-q", "main")
            try harness.fixture.write("a.txt", "main side\n")
            try await harness.fixture.commit("main edits a")
            try await harness.fixture.run("checkout", "-q", "feature")
            await harness.model.reload()
            let main = try #require(harness.anyRow("main")?.ref)

            harness.model.rebaseCurrent(onto: main)

            try await eventually { harness.model.operationState.isRebasing }
            let ongoing = harness.model.rows.compactMap(\.ongoingAction)
            #expect(ongoing == [.rebaseAbort, .rebaseContinue, .rebaseSkip])
            try await eventually { harness.notifications.contains { $0.title == "Rebase stopped with conflicts" } }

            harness.model.performOngoing(.rebaseAbort)
            try await eventually { harness.model.operationState == .none }
        }
    }

    @Test
    func newBranchDialogCanCreateWithoutCheckout() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            var request: BranchesPopupBranchDialogRequest?
            harness.model.dialogs.branchDialog = { dialogRequest in
                request = dialogRequest
                return BranchesPopupBranchDialogResult(
                    name: "created",
                    checkout: false,
                    overwrite: false,
                    unsetUpstream: false
                )
            }
            let feature = try #require(harness.anyRow("feature")?.ref)

            harness.model.promptNewBranch(from: feature)

            #expect(request?.showsCheckout == true)
            #expect(request?.existingNames.contains("obsolete") == true)
            try await eventually { (try? await harness.branches())?.contains("created") == true }
            #expect(harness.manager.currentBranch?.name == "main")
        }
    }

    @Test
    func newBranchDialogCanOverwriteAnExistingBranch() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            harness.model.dialogs.branchDialog = { _ in
                BranchesPopupBranchDialogResult(
                    name: "obsolete",
                    checkout: false,
                    overwrite: true,
                    unsetUpstream: false
                )
            }
            let featureTip = try await harness.fixture.run("rev-parse", "feature")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let feature = try #require(harness.anyRow("feature")?.ref)

            harness.model.promptNewBranch(from: feature)

            try await eventually {
                let tip = try? await harness.fixture.run("rev-parse", "obsolete")
                return tip?.trimmingCharacters(in: .whitespacesAndNewlines) == featureTip
            }
            #expect(harness.manager.currentBranch?.name == "main")
        }
    }

    @Test
    func invalidBranchNameShowsAnErrorAndDoesNothing() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            harness.model.dialogs.branchDialog = { _ in
                BranchesPopupBranchDialogResult(name: "bad name", checkout: false)
            }
            let feature = try #require(harness.anyRow("feature")?.ref)

            harness.model.promptNewBranch(from: feature)

            #expect(harness.errors == ["Invalid Branch Name"])
            #expect(try await harness.branches().contains("bad name") == false)
        }
    }

    @Test
    func renameDialogOffersUnsetUpstream() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            try await harness.fixture.run("branch", "--set-upstream-to=main", "obsolete")
            await harness.model.reload()
            var request: BranchesPopupBranchDialogRequest?
            harness.model.dialogs.branchDialog = { dialogRequest in
                request = dialogRequest
                return BranchesPopupBranchDialogResult(
                    name: "renamed",
                    checkout: false,
                    overwrite: false,
                    unsetUpstream: true
                )
            }
            let obsolete = try #require(harness.anyRow("obsolete")?.ref)

            harness.model.promptRename(obsolete)

            #expect(request?.showsUnsetUpstream == true)
            try await eventually {
                let renamed = (try? await harness.branches())?.contains("renamed") == true
                let upstream = await harness.upstream(of: "renamed")
                return renamed && upstream == nil
            }
            #expect(try await harness.branches().contains("obsolete") == false)
        }
    }

    @Test
    func deletingUnmergedBranchRequiresForceAndCanBeRestored() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            try await harness.fixture.run("checkout", "-q", "-b", "unmerged")
            try harness.fixture.write("u.txt", "u\n")
            try await harness.fixture.commit("unmerged work")
            try await harness.fixture.run("checkout", "-q", "main")
            await harness.model.reload()
            let unmerged = try #require(harness.anyRow("unmerged")?.ref)
            harness.model.dialogs.unmergedDelete = { name, commits in
                #expect(name == "unmerged")
                #expect(commits.isEmpty == false)
                return .force
            }

            harness.model.delete(unmerged)

            try await eventually { (try? await harness.branches())?.contains("unmerged") == false }
            #expect(harness.manager.lastAlert == nil)
            try await eventually { harness.notifications.contains { $0.title == "Deleted Branch: unmerged" } }
            let notification = try #require(harness.notifications.first { $0.title == "Deleted Branch: unmerged" })
            #expect(notification.actionTitle == "Restore")

            notification.action()
            try await eventually { (try? await harness.branches())?.contains("unmerged") == true }
        }
    }

    @Test
    func deletingMergedBranchDoesNotAskForForce() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            harness.model.dialogs.unmergedDelete = { _, _ in
                Issue.record("force delete must not be offered for a merged branch")
                return .cancel
            }
            let obsolete = try #require(harness.anyRow("obsolete")?.ref)

            harness.model.delete(obsolete)

            try await eventually { (try? await harness.branches())?.contains("obsolete") == false }
            try await eventually { harness.notifications.contains { $0.title == "Deleted Branch: obsolete" } }
        }
    }

    @Test
    func deletingTagNotifiesWithRestore() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            harness.model.toggleExpansion(.section(.tags))
            let tag = try #require(harness.refRow(.tag, "v1.0")?.ref)

            harness.model.delete(tag)

            try await eventually {
                ((try? await harness.fixture.run("tag")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            try await eventually { harness.notifications.contains { $0.title == "Deleted Tag: v1.0" } }
            let notification = try #require(harness.notifications.first { $0.title == "Deleted Tag: v1.0" })
            notification.action()
            try await eventually { ((try? await harness.fixture.run("tag")) ?? "").contains("v1.0") }
        }
    }

    @Test
    func deletingRemoteBranchCanAlsoDeleteTrackingBranches() async throws {
        try await withTempDir { dir in
            let originRoot = dir.appending(path: "origin")
            try FileManager.default.createDirectory(at: originRoot, withIntermediateDirectories: true)
            let origin = try await GitMergeFixture(root: originRoot)
            try origin.write("a.txt", "one\n")
            try await origin.commit("initial")
            try await origin.run("branch", "doomed")

            let cloneRoot = dir.appending(path: "clone")
            try await origin.run(
                "clone",
                "-q",
                origin.root.path(percentEncoded: false),
                cloneRoot.path(percentEncoded: false)
            )
            let cloneFixture = GitMergeFixture(existing: cloneRoot)
            try await cloneFixture.run("config", "user.email", "clone@dreamder.test")
            try await cloneFixture.run("config", "user.name", "Clone")
            try await cloneFixture.run("branch", "--track", "doomed", "origin/doomed")

            let harness = try await loaded(cloneRoot, existing: true)
            harness.model.dialogs.confirm = { title, _, _ in
                title == "Delete Remote Branch" || title == "Delete Tracking Branches"
            }
            let doomed = try #require(harness.model.remoteBranchRefs.first { $0.shortName == "origin/doomed" })
            #expect(doomed.kind == .remote)

            harness.model.delete(doomed)

            try await eventually {
                (try? await origin.run("branch", "--format=%(refname:short)"))?.contains("doomed") == false
            }
            try await eventually { (try? await harness.branches())?.contains("doomed") == false }
        }
    }

    @Test
    func checkoutRemoteWithLocalCommitsUsesInjectedDecision() async throws {
        try await withTempDir { dir in
            let originRoot = dir.appending(path: "origin")
            try FileManager.default.createDirectory(at: originRoot, withIntermediateDirectories: true)
            let origin = try await GitMergeFixture(root: originRoot)
            try origin.write("a.txt", "base\n")
            try await origin.commit("initial")
            try await origin.run("branch", "feature")

            let cloneRoot = dir.appending(path: "clone")
            try await origin.run(
                "clone",
                "-q",
                origin.root.path(percentEncoded: false),
                cloneRoot.path(percentEncoded: false)
            )
            let cloneFixture = GitMergeFixture(existing: cloneRoot)
            try await cloneFixture.run("config", "user.email", "clone@dreamder.test")
            try await cloneFixture.run("config", "user.name", "Clone")
            try await cloneFixture.run("checkout", "-q", "-b", "feature", "--track", "origin/feature")
            try cloneFixture.write("local.txt", "local\n")
            try await cloneFixture.commit("local work")
            try await origin.run("checkout", "-q", "feature")
            try origin.write("remote.txt", "remote\n")
            try await origin.commit("remote work")
            try await cloneFixture.run("fetch", "-q", "origin")

            let harness = try await loaded(cloneRoot, existing: true)
            var decisions = 0
            harness.model.dialogs.checkoutRemoteLocalCommits = { local, remote, count in
                decisions += 1
                #expect(local == "feature")
                #expect(remote == "origin/feature")
                #expect(count == 1)
                return .rebase
            }
            let remote = try #require(harness.anyRow("origin/feature")?.ref)

            harness.model.checkout(remote)

            try await eventually {
                harness.manager.currentBranch?.name == "feature" && harness.fixture.exists("remote.txt")
            }
            #expect(decisions == 1)
        }
    }

    @Test
    func checkoutRemoteWithTrackingConflictAsksForANewName() async throws {
        try await withTempDir { dir in
            let originRoot = dir.appending(path: "origin")
            try FileManager.default.createDirectory(at: originRoot, withIntermediateDirectories: true)
            let origin = try await GitMergeFixture(root: originRoot)
            try origin.write("a.txt", "base\n")
            try await origin.commit("initial")
            try await origin.run("branch", "feature")

            let cloneRoot = dir.appending(path: "clone")
            try await origin.run(
                "clone",
                "-q",
                origin.root.path(percentEncoded: false),
                cloneRoot.path(percentEncoded: false)
            )
            let cloneFixture = GitMergeFixture(existing: cloneRoot)
            try await cloneFixture.run("config", "user.email", "clone@dreamder.test")
            try await cloneFixture.run("config", "user.name", "Clone")
            try await cloneFixture.run("checkout", "-q", "-b", "feature", "--track", "origin/main")
            try await cloneFixture.run("checkout", "-q", "main")

            let harness = try await loaded(cloneRoot, existing: true)
            harness.model.dialogs.checkoutRemoteName = { remote, suggested in
                #expect(remote == "origin/feature")
                #expect(suggested == "feature")
                return "feature-local"
            }
            let remote = try #require(harness.anyRow("origin/feature")?.ref)

            harness.model.checkout(remote)

            try await eventually { harness.manager.currentBranch?.name == "feature-local" }
            #expect(await harness.upstream(of: "feature-local") == "origin/feature")
        }
    }

    @Test
    func compareWithCurrentUsesThePresenter() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            let feature = try #require(harness.anyRow("feature")?.ref)

            harness.model.compareWithCurrent(feature)

            #expect(harness.compares.map(\.branch) == ["feature"])
            #expect(harness.compares.map(\.current) == ["main"])
            #expect(harness.dismissals == 1)
        }
    }

    @Test
    func favoritesTogglePersistAndFloatToTheTop() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            try await harness.fixture.run("branch", "alpha")
            await harness.model.reload()
            let obsolete = try #require(harness.anyRow("obsolete")?.ref)

            harness.model.toggleFavorite(obsolete)
            #expect(harness.model.favorites.contains("local:obsolete"))
            #expect(harness.model.rows.first { $0.ref?.shortName == "obsolete" }?.isFavorite == true)

            let localSection = try #require(harness.model.sections.first { $0.id == .local })
            let localTitles = localSection.nodes.map(\.title).filter { $0 != "main" }
            #expect(localTitles == ["obsolete", "alpha", "feature"])

            harness.model.toggleFavorite(obsolete)
            #expect(harness.model.favorites.contains("local:obsolete") == false)
            let restored = try #require(harness.model.sections.first { $0.id == .local })
            let restoredTitles = restored.nodes.map(\.title).filter { $0 != "main" }
            #expect(restoredTitles == ["alpha", "feature", "obsolete"])
        }
    }

    @Test
    func mainBranchesAreFavoriteByDefaultAndCanBeExcluded() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            let main = try #require(harness.anyRow("main")?.ref)
            #expect(harness.model.favorites.contains("local:main"))
            #expect(harness.model.favorites.contains("local:feature") == false)

            harness.model.toggleFavorite(main)
            #expect(harness.model.favorites.contains("local:main") == false)

            let reopened = try await loaded(dir, existing: true)
            #expect(reopened.model.favorites.contains("local:main") == false)
            #expect(reopened.model.favorites.contains("remote:origin/main"))

            reopened.model.toggleFavorite(main)
            let again = try await loaded(dir, existing: true)
            #expect(again.model.favorites.contains("local:main"))
        }
    }

    @Test
    func trackingBranchCanBeSetAndCleared() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            let obsolete = try #require(harness.anyRow("obsolete")?.ref)

            harness.model.setUpstream(obsolete, to: "main")
            try await eventually { await harness.upstream(of: "obsolete") == "main" }

            harness.model.setUpstream(obsolete, to: nil)
            try await eventually { await harness.upstream(of: "obsolete") == nil }
        }
    }

    @Test
    func pushAndCommitActionsRouteToTheirUI() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            let feature = try #require(harness.anyRow("feature")?.ref)

            harness.model.push(feature)
            #expect(harness.manager.pushSheetIsPresented)
            #expect(harness.manager.operationBranch?.name == "feature")

            harness.manager.pushSheetIsPresented = false
            harness.model.perform(.push)
            #expect(harness.manager.pushSheetIsPresented)
            #expect(harness.manager.operationBranch?.name == "main")

            harness.model.perform(.commit)
            #expect(harness.workspace.toolWindowManager.isVisible(.commit))
            #expect(harness.dismissals == 3)
        }
    }

    @Test
    func hidingTagsRemovesTheSectionAndIsRemembered() async throws {
        let defaults = self.defaults
        let previous = defaults.object(forKey: BranchesPopupViewModel.showTagsKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: BranchesPopupViewModel.showTagsKey)
            } else {
                defaults.removeObject(forKey: BranchesPopupViewModel.showTagsKey)
            }
        }
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            harness.model.showsTags = false

            #expect(harness.model.sections.map(\.id).contains(.tags) == false)
            #expect(defaults.bool(forKey: BranchesPopupViewModel.showTagsKey) == false)

            harness.model.showsTags = true
            #expect(harness.model.sections.map(\.id).contains(.tags))
        }
    }

    @Test
    func groupByDirectoryTogglesNestedNames() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            try await harness.fixture.run("branch", "team/nested")
            await harness.model.reload()
            harness.model.showsRecentBranches = false
            harness.model.groupsByDirectory = true
            #expect(harness.model.sections.first { $0.id == .local }?.nodes.contains { $0.kind == .group } == true)

            harness.model.groupsByDirectory = false
            #expect(harness.model.sections.first { $0.id == .local }?.nodes.contains { $0.kind == .group } == false)
        }
    }
}

extension BranchesPopupViewModelTests {
    private struct ClonePair {
        let origin: GitMergeFixture
        let clone: GitMergeFixture
    }

    private func makeClone(in dir: URL) async throws -> ClonePair {
        let originRoot = dir.appending(path: "origin")
        try FileManager.default.createDirectory(at: originRoot, withIntermediateDirectories: true)
        let origin = try await GitMergeFixture(root: originRoot)
        try origin.write("a.txt", "base\n")
        try await origin.commit("initial")
        try await origin.run("branch", "feature")
        let cloneRoot = dir.appending(path: "clone")
        try await origin.run(
            "clone",
            "-q",
            origin.root.path(percentEncoded: false),
            cloneRoot.path(percentEncoded: false)
        )
        let clone = GitMergeFixture(existing: cloneRoot)
        try await clone.run("config", "user.email", "clone@dreamder.test")
        try await clone.run("config", "user.name", "Clone")
        return ClonePair(origin: origin, clone: clone)
    }

    private func makeDivergedFeatureClone(
        in dir: URL,
        localFile: String = "local.txt",
        remoteFile: String = "remote.txt"
    ) async throws -> ClonePair {
        let pair = try await makeClone(in: dir)
        try await pair.clone.run("checkout", "-q", "-b", "feature", "--track", "origin/feature")
        try pair.clone.write(localFile, "local\n")
        try await pair.clone.commit("local work")
        try await pair.clone.run("checkout", "-q", "main")
        try await pair.origin.run("checkout", "-q", "feature")
        try pair.origin.write(remoteFile, "remote\n")
        try await pair.origin.commit("remote work")
        try await pair.origin.run("checkout", "-q", "main")
        try await pair.clone.run("fetch", "-q", "origin")
        return pair
    }

    private func startConflictingMerge(in harness: Harness) async throws {
        try await harness.fixture.run("checkout", "-q", "feature")
        try harness.fixture.write("a.txt", "feature side\n")
        try await harness.fixture.commit("feature edits a")
        try await harness.fixture.run("checkout", "-q", "main")
        try harness.fixture.write("a.txt", "main side\n")
        try await harness.fixture.commit("main edits a")
        _ = try await harness.fixture.runIgnoringFailure("merge", "--no-edit", "feature")
    }

    private func ghostRef(_ kind: BranchesPopupRef.Kind, _ shortName: String, upstream: String? = nil) -> BranchesPopupRef {
        BranchesPopupRef(
            kind: kind,
            name: kind == .remote ? String(shortName.split(separator: "/", maxSplits: 1).last ?? "") : shortName,
            shortName: shortName,
            upstream: upstream,
            isCurrent: false
        )
    }

    @Test
    func ongoingActionsAreListedBeforeNewBranchAndSurviveASearchThatMatchesNoAction() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            try await startConflictingMerge(in: harness)
            await harness.model.reload()
            #expect(harness.model.operationState.isMerging)

            let expected: [BranchesPopupItemID] = [
                .action(.updateProject),
                .action(.commit),
                .action(.push),
                .separator("action-groups"),
                .ongoing(.mergeAbort),
                .action(.newBranch),
                .action(.newWorktree),
                .action(.checkoutRevision),
                .separator("actions-end")
            ]
            let leading = Array(harness.model.rows.map(\.id).prefix(expected.count))
            #expect(leading == expected)

            harness.model.query = "zzz-no-match"
            let remaining: [BranchesPopupItemID] = [.ongoing(.mergeAbort), .separator("actions-end")]
            #expect(harness.model.rows.map(\.id) == remaining)
            #expect(harness.model.emptyMessage == nil)

            let abort = try #require(harness.model.rows.first { $0.ongoingAction == .mergeAbort })
            harness.model.activate(abort)
            try await eventually { harness.model.operationState == .none }
            #expect(try await harness.fixture.unmergedPaths().isEmpty)
        }
    }

    @Test
    func actionsCanBeHiddenFromSearchAndWhitespaceQueriesBehaveLikeNoQuery() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            let model = harness.model
            let initialRows = model.rows

            model.query = "   "
            #expect(model.rows == initialRows)
            #expect(model.visibleActions == BranchesPopupActionID.allCases)

            model.query = "new"
            #expect(model.visibleActions.contains(.newBranch))
            #expect(model.visibleActions.contains(.newWorktree))
            #expect(model.visibleActions.contains(.commit) == false)

            model.showsActionsInSearch = false
            #expect(model.visibleActions.isEmpty)
            #expect(defaults.bool(forKey: BranchesPopupViewModel.showActionsKey) == false)

            model.query = ""
            #expect(model.visibleActions == BranchesPopupActionID.allCases)
        }
    }

    @Test
    func activatingTheSelectedActionRowPerformsIt() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)

            harness.model.selectedID = .action(.commit)
            harness.model.activateSelection()

            #expect(harness.workspace.toolWindowManager.isVisible(.commit))
            #expect(harness.dismissals == 1)
        }
    }

    @Test
    func newBranchActionAsksForANameTrimsItAndChecksTheBranchOut() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            var request: BranchesPopupBranchDialogRequest?
            var blockedWhileAsking = false
            harness.model.dialogs.branchDialog = { dialogRequest in
                request = dialogRequest
                blockedWhileAsking = harness.model.isBlockingInput
                return BranchesPopupBranchDialogResult(name: "  topic  ")
            }

            harness.model.perform(.newBranch)

            #expect(request?.title == "New Branch")
            #expect(request?.message == "Create a new branch")
            #expect(request?.initialName == "main")
            #expect(request?.confirmTitle == "Create")
            #expect(request?.showsCheckout == true)
            #expect(request?.showsUnsetUpstream == false)
            #expect(blockedWhileAsking)
            #expect(harness.model.isBlockingInput == false)
            #expect(harness.dismissals == 1)
            try await eventually { harness.manager.currentBranch?.name == "topic" }
        }
    }

    @Test
    func newBranchIsDroppedOnCancelAndRejectedForEmptyOrTakenNames() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            var answer: BranchesPopupBranchDialogResult?
            harness.model.dialogs.branchDialog = { _ in answer }

            harness.model.perform(.newBranch)
            #expect(harness.errors.isEmpty)

            answer = BranchesPopupBranchDialogResult(name: "obsolete")
            harness.model.perform(.newBranch)
            #expect(harness.errors == ["Invalid Branch Name"])

            answer = BranchesPopupBranchDialogResult(name: "   ")
            harness.model.perform(.newBranch)
            #expect(harness.errors == ["Invalid Branch Name", "Invalid Branch Name"])

            #expect(harness.dismissals == 0)
            #expect(harness.model.runningOperations == 0)
            #expect(try await harness.branches() == ["feature", "main", "obsolete"])
        }
    }

    @Test
    func renamingValidatesTheNewNameAndIgnoresUnchangedNames() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            var request: BranchesPopupBranchDialogRequest?
            var answer: BranchesPopupBranchDialogResult?
            harness.model.dialogs.branchDialog = { dialogRequest in
                request = dialogRequest
                return answer
            }
            let obsolete = try #require(harness.anyRow("obsolete")?.ref)

            answer = BranchesPopupBranchDialogResult(name: "obsolete")
            harness.model.promptRename(obsolete)
            #expect(harness.model.runningOperations == 0)
            #expect(harness.errors.isEmpty)

            answer = BranchesPopupBranchDialogResult(name: "feature")
            harness.model.promptRename(obsolete)
            #expect(harness.errors == ["Invalid Branch Name"])
            #expect(harness.model.runningOperations == 0)

            answer = BranchesPopupBranchDialogResult(name: "renamed")
            harness.model.promptRename(obsolete)
            try await eventually { (try? await harness.branches())?.contains("renamed") == true }
            #expect(try await harness.branches().contains("obsolete") == false)

            #expect(request?.title == "Rename Branch obsolete")
            #expect(request?.message == "Rename 'obsolete' to:")
            #expect(request?.initialName == "obsolete")
            #expect(request?.confirmTitle == "Rename")
            #expect(request?.showsCheckout == false)
            #expect(request?.showsUnsetUpstream == false)
            #expect(request?.existingNames.contains("feature") == true)
            #expect(request?.existingNames.contains("obsolete") == false)
        }
    }

    @Test
    func arrowKeysStepThroughSelectableRowsInOrderAndSkipSeparators() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            let model = harness.model
            let selectable = model.rows.filter(\.isSelectable).map(\.id)
            #expect(model.rows.contains { $0.kind == .separator })
            #expect(selectable.count > 3)

            model.selectedID = selectable.first
            var visited: [BranchesPopupItemID] = []
            for _ in selectable.dropFirst() {
                model.moveSelection(1)
                if let id = model.selectedID { visited.append(id) }
            }
            #expect(visited == Array(selectable.dropFirst()))

            model.selectedID = selectable[2]
            model.moveSelection(-1)
            #expect(model.selectedID == selectable[1])
            model.moveSelection(-1)
            model.moveSelection(-1)
            #expect(model.selectedID == selectable.last)
        }
    }

    @Test
    func navigationActivationAndFavoritesDoNothingWithoutSelectableRows() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            let model = harness.model
            let favoritesBefore = model.favorites

            model.query = "zzz-no-branch"
            #expect(model.rows.isEmpty)
            #expect(model.selectedID == nil)

            model.moveSelection(1)
            model.moveSelection(-1)
            model.activateSelection()
            model.toggleSelectionExpansion()
            model.toggleSelectedFavorite()

            #expect(model.selectedID == nil)
            #expect(harness.presentedRefs.isEmpty)
            #expect(harness.dismissals == 0)
            #expect(model.favorites == favoritesBefore)
        }
    }

    @Test
    func activatingGroupsCollapsesThemAndSeparatorsDoNothing() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            try await harness.fixture.run("branch", "team/nested")
            await harness.model.reload()
            harness.model.showsRecentBranches = false
            let group = BranchesPopupItemID.group(.local, "team")
            let groupRow = try #require(harness.model.rows.first { $0.id == group })
            #expect(groupRow.isExpanded)
            #expect(harness.refRow(.local, "team/nested") != nil)

            harness.model.activate(groupRow)

            #expect(harness.model.collapsedGroups == [group])
            #expect(harness.model.isExpanded(group) == false)
            #expect(harness.refRow(.local, "team/nested") == nil)
            let collapsedRow = try #require(harness.model.rows.first { $0.id == group })
            #expect(collapsedRow.isExpanded == false)

            harness.model.selectedID = group
            harness.model.toggleSelectionExpansion()
            #expect(harness.model.collapsedGroups.isEmpty)
            #expect(harness.refRow(.local, "team/nested") != nil)

            let separator = try #require(harness.model.rows.first { $0.kind == .separator })
            let rowsBefore = harness.model.rows
            harness.model.activate(separator)
            #expect(harness.model.rows == rowsBefore)
            #expect(harness.dismissals == 0)
            #expect(harness.presentedRefs.isEmpty)
        }
    }

    @Test
    func selectedSectionTogglesAndSearchCollapsesFlipBackAndForth() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            let model = harness.model
            let local = BranchesPopupItemID.section(.local)

            model.selectedID = local
            model.toggleSelectionExpansion()
            #expect(model.isExpanded(local) == false)
            model.toggleSelectionExpansion()
            #expect(model.isExpanded(local))

            model.query = "obsolete"
            model.toggleExpansion(local)
            #expect(model.collapsedWhileSearching == [local])
            model.toggleExpansion(local)
            #expect(model.collapsedWhileSearching.isEmpty)
            #expect(model.isExpanded(local))

            let before = model.expandedIDs
            model.toggleExpansion(.ref(.local, "main"))
            model.toggleExpansion(.action(.commit))
            model.toggleExpansion(.separator("actions-end"))
            #expect(model.expandedIDs == before)
            #expect(model.collapsedGroups.isEmpty)
            #expect(model.isExpanded(.ref(.local, "main")) == false)
            #expect(model.isExpanded(.action(.commit)) == false)
        }
    }

    @Test
    func toggleSelectedFavoriteStarsTheSelectedBranchOnly() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            let model = harness.model
            let obsolete = try #require(harness.refRow(.local, "obsolete"))
            model.selectedID = obsolete.id

            model.toggleSelectedFavorite()

            #expect(model.favorites.contains("local:obsolete"))
            let afterFirst = model.favorites

            model.selectedID = .action(.commit)
            model.toggleSelectedFavorite()
            #expect(model.favorites == afterFirst)

            model.selectedID = obsolete.id
            model.toggleSelectedFavorite()
            #expect(model.favorites.contains("local:obsolete") == false)
        }
    }

    @Test
    func rowIconsReflectCurrentFavoriteAndTagState() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            let model = harness.model
            let current = try #require(model.rows.first { $0.ref?.isCurrent == true })
            let currentRef = try #require(current.ref)
            #expect(current.iconName == "vcs/currentBranchFavoriteLabel")

            let feature = try #require(harness.refRow(.local, "feature"))
            let featureRef = try #require(feature.ref)
            #expect(feature.iconName == "general/vcs")

            model.toggleFavorite(featureRef)
            #expect(harness.refRow(.local, "feature")?.iconName == "nodes/star")

            model.toggleFavorite(currentRef)
            #expect(model.rows.first { $0.ref?.isCurrent == true }?.iconName == "vcs/currentBranchLabel")

            model.toggleExpansion(.section(.tags))
            #expect(harness.refRow(.tag, "v1.0")?.iconName == "vcs/branchLabel")
        }
    }

    @Test
    func favoritesAreStoredPerRepositoryWithoutPredefinedEntries() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            let obsolete = try #require(harness.anyRow("obsolete")?.ref)
            harness.model.toggleFavorite(obsolete)

            let otherDir = dir.appending(path: "other")
            try FileManager.default.createDirectory(at: otherDir, withIntermediateDirectories: true)
            let other = try await loaded(otherDir)

            #expect(harness.model.favorites.contains("local:obsolete"))
            #expect(other.model.favorites.contains("local:obsolete") == false)
            let path = harness.manager.repositoryURL.path(percentEncoded: false)
            let stored = defaults.stringArray(forKey: BranchesPopupViewModel.favoritesKeyPrefix + path)
            #expect(stored == ["local:obsolete"])
            let excluded = defaults.stringArray(forKey: BranchesPopupViewModel.excludedFavoritesKeyPrefix + path)
            #expect((excluded ?? []).isEmpty)
        }
    }

    @Test
    func predefinedRemoteFavoritesCanBeExcludedAndRestoredAcrossPopups() async throws {
        try await withTempDir { dir in
            let pair = try await makeClone(in: dir)
            let harness = try await loaded(pair.clone.root, existing: true)
            let remoteMain = try #require(harness.model.remoteBranchRefs.first { $0.shortName == "origin/main" })
            let remoteSection = try #require(harness.model.sections.first { $0.id == .remote })
            #expect(remoteSection.nodes.first?.children.map(\.title) == ["main", "feature"])

            harness.model.toggleFavorite(remoteMain)
            #expect(harness.model.favorites.contains("remote:origin/main") == false)
            let reorderedSection = try #require(harness.model.sections.first { $0.id == .remote })
            #expect(reorderedSection.nodes.first?.children.map(\.title) == ["feature", "main"])

            let path = harness.manager.repositoryURL.path(percentEncoded: false)
            let excludedKey = BranchesPopupViewModel.excludedFavoritesKeyPrefix + path
            let storedKey = BranchesPopupViewModel.favoritesKeyPrefix + path
            #expect(defaults.stringArray(forKey: excludedKey) == ["remote:origin/main"])
            #expect((defaults.stringArray(forKey: storedKey) ?? []).isEmpty)

            let reopened = try await loaded(pair.clone.root, existing: true)
            #expect(reopened.model.favorites.contains("remote:origin/main") == false)
            #expect(reopened.model.favorites.contains("local:main"))

            reopened.model.toggleFavorite(remoteMain)
            #expect(reopened.model.favorites.contains("remote:origin/main"))
            #expect((defaults.stringArray(forKey: excludedKey) ?? []).isEmpty)
            #expect((defaults.stringArray(forKey: storedKey) ?? []).isEmpty)

            let restored = try await loaded(pair.clone.root, existing: true)
            #expect(restored.model.favorites.contains("remote:origin/main"))
        }
    }

    @Test
    func displayOptionsDefaultToOnAndAreRestoredByANewPopup() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            #expect(harness.model.showsRecentBranches)
            #expect(harness.model.showsTags)
            #expect(harness.model.groupsByDirectory)
            #expect(harness.model.showsActionsInSearch)

            harness.model.showsRecentBranches = false
            harness.model.showsTags = false
            harness.model.groupsByDirectory = false
            harness.model.showsActionsInSearch = false

            let reopened = try await loaded(dir, existing: true)
            #expect(reopened.model.showsRecentBranches == false)
            #expect(reopened.model.showsTags == false)
            #expect(reopened.model.groupsByDirectory == false)
            #expect(reopened.model.showsActionsInSearch == false)
            #expect(reopened.model.sections.map(\.id) == [.local])
        }
    }

    @Test
    func hidingRecentBranchesMovesThePreferredSelectionToTheLocalSection() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            let model = harness.model
            #expect(model.selectedID == .ref(.recent, "feature"))

            model.showsRecentBranches = false

            #expect(model.sections.map(\.id).contains(.recent) == false)
            #expect(model.selectedID == .ref(.local, "feature"))
            #expect(defaults.bool(forKey: BranchesPopupViewModel.showRecentBranchesKey) == false)

            model.showsRecentBranches = true
            #expect(model.sections.map(\.id).contains(.recent))
            #expect(model.selectedID == .ref(.local, "feature"))
        }
    }

    @Test
    func tagsAreSearchableAndCanBeHiddenFromTheTree() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            harness.model.query = "v1"

            #expect(harness.refRow(.tag, "v1.0") != nil)
            #expect(harness.model.sections.map(\.id) == [.tags])
            #expect(harness.model.selectedRow?.ref?.kind == .tag)

            harness.model.showsTags = false

            #expect(harness.model.sections.isEmpty)
            #expect(harness.model.selectedID == nil)
            #expect(harness.model.emptyMessage == "Nothing found")
        }
    }

    @Test
    func selectionFallsBackToAVisibleMatchWhenThePreferredBranchIsCollapsed() async throws {
        try await withTempDir { dir in
            let pair = try await makeClone(in: dir)
            try await pair.clone.run("checkout", "-q", "-b", "feature", "--track", "origin/feature")
            try await pair.clone.run("checkout", "-q", "main")
            let harness = try await loaded(pair.clone.root, existing: true)
            let model = harness.model

            model.query = "feat"
            #expect(model.selectedID == .ref(.recent, "feature"))

            model.toggleExpansion(.section(.recent))
            model.query = "featu"

            #expect(model.selectedID == .ref(.remote, "origin/feature"))
        }
    }

    @Test
    func remoteBranchRefsAreSortedIgnoringCaseAndSkipHeadAndMalformedRemotes() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            let extra = [
                GitBranch(name: "origin/Zeta", longName: "refs/remotes/origin/Zeta", upstream: nil, ahead: 0, behind: 0),
                GitBranch(name: "origin/alpha", longName: "refs/remotes/origin/alpha", upstream: nil, ahead: 0, behind: 0),
                GitBranch(name: "origin/HEAD", longName: "refs/remotes/origin/HEAD", upstream: nil, ahead: 0, behind: 0),
                GitBranch(name: "orphan", longName: "refs/remotes/orphan", upstream: nil, ahead: 0, behind: 0)
            ]
            harness.manager.branches = harness.manager.branches + extra

            let refs = harness.model.remoteBranchRefs

            #expect(refs.map(\.shortName) == ["origin/alpha", "origin/Zeta"])
            #expect(refs.map(\.name) == ["alpha", "Zeta"])
            #expect(refs.allSatisfy { $0.kind == .remote && $0.upstream == nil && !$0.isCurrent })
        }
    }

    @Test
    func actionContextReportsRemotesTrackedBranchAndDetachedHead() async throws {
        try await withTempDir { dir in
            let pair = try await makeClone(in: dir)
            try await pair.clone.run("branch", "--track", "feature", "origin/feature")
            try await pair.clone.run("branch", "local-only")
            let harness = try await loaded(pair.clone.root, existing: true)
            let model = harness.model
            await harness.manager.branchOpsRefresh()
            #expect(model.remoteNames == ["origin"])

            let feature = try #require(harness.anyRow("feature")?.ref)
            let context = model.refActionContext(for: feature)
            #expect(context.currentName == "main")
            #expect(context.hasRemotes)
            #expect(context.isDetachedHead == false)
            #expect(context.trackedBranch?.shortName == "origin/feature")
            #expect(context.trackedBranch?.kind == .remote)

            let localOnly = try #require(harness.anyRow("local-only")?.ref)
            #expect(model.refActionContext(for: localOnly).trackedBranch == nil)

            let remote = try #require(model.remoteBranchRefs.first { $0.shortName == "origin/feature" })
            #expect(model.refActionContext(for: remote).trackedBranch == nil)

            try await pair.origin.run("branch", "-D", "feature")
            try await pair.clone.run("fetch", "-q", "--prune")
            await model.reload()
            let orphaned = try #require(harness.anyRow("feature")?.ref)
            #expect(model.refActionContext(for: orphaned).trackedBranch == nil)
        }
    }

    @Test
    func detachedHeadIsNamedHeadAndComparesAgainstIt() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            try await harness.fixture.run("checkout", "-q", "--detach")
            await harness.model.reload()
            let model = harness.model

            #expect(model.currentBranchName == "HEAD")
            #expect(model.rows.contains { $0.ref?.isCurrent == true } == false)
            let feature = try #require(harness.anyRow("feature")?.ref)
            let context = model.refActionContext(for: feature)
            #expect(context.isDetachedHead)
            #expect(context.currentName == "HEAD")
            #expect(context.hasRemotes == false)
            #expect(context.trackedBranch == nil)

            model.compareWithCurrent(feature)
            #expect(harness.compares.map(\.current) == ["HEAD"])
        }
    }

    @Test
    func comparingUsesRemoteShortNamesAndIgnoresTheCurrentBranch() async throws {
        try await withTempDir { dir in
            let pair = try await makeClone(in: dir)
            let harness = try await loaded(pair.clone.root, existing: true)
            let main = try #require(harness.anyRow("main")?.ref)
            let remote = try #require(harness.model.remoteBranchRefs.first { $0.shortName == "origin/feature" })

            harness.model.compareWithCurrent(main)
            #expect(harness.compares.isEmpty)
            #expect(harness.dismissals == 0)

            harness.model.compareWithCurrent(remote)
            #expect(harness.compares.map(\.branch) == ["origin/feature"])
            #expect(harness.compares.map(\.current) == ["main"])
            #expect(harness.dismissals == 1)
        }
    }

    @Test
    func fetchPullsInNewRemoteBranchesPrunesDeletedOnesAndClearsTheFlag() async throws {
        try await withTempDir { dir in
            let pair = try await makeClone(in: dir)
            let harness = try await loaded(pair.clone.root, existing: true)
            #expect(harness.model.remoteBranchRefs.map(\.shortName) == ["origin/feature", "origin/main"])
            try await pair.origin.run("branch", "hotfix")
            try await pair.origin.run("branch", "-D", "feature")

            harness.model.fetch()
            #expect(harness.model.isFetching)
            harness.model.fetch()

            try await eventually { harness.model.isFetching == false }
            #expect(harness.model.remoteBranchRefs.map(\.shortName) == ["origin/hotfix", "origin/main"])
            #expect(harness.anyRow("origin/hotfix") != nil)
            #expect(harness.anyRow("origin/feature") == nil)
            #expect(harness.manager.lastAlert == nil)
        }
    }

    @Test
    func fetchFailureIsReportedAndStopsTheSpinner() async throws {
        try await withTempDir { dir in
            let pair = try await makeClone(in: dir)
            let harness = try await loaded(pair.clone.root, existing: true)
            let missing = dir.appending(path: "missing").path(percentEncoded: false)
            try await pair.clone.run("remote", "set-url", "origin", missing)

            harness.model.fetch()

            try await eventually { harness.manager.lastAlert?.title == "Fetch failed" && !harness.model.isFetching }
            #expect(harness.manager.lastAlert?.message.isEmpty == false)
        }
    }

    @Test
    func updateProjectPullsTheCurrentBranchFromItsRemote() async throws {
        try await withTempDir { dir in
            let pair = try await makeClone(in: dir)
            try pair.origin.write("remote.txt", "remote\n")
            try await pair.origin.commit("remote work")
            let harness = try await loaded(pair.clone.root, existing: true)

            harness.model.perform(.updateProject)

            #expect(harness.dismissals == 1)
            try await eventually { harness.fixture.exists("remote.txt") }
        }
    }

    @Test
    func updateProjectWithoutATrackedRemoteReportsAnError() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)

            harness.model.perform(.updateProject)

            #expect(harness.dismissals == 1)
            try await eventually { harness.manager.lastAlert?.title == "Failed to update project" }
        }
    }

    @Test
    func updatingBranchesFastForwardsThemFromTheirUpstream() async throws {
        try await withTempDir { dir in
            let pair = try await makeClone(in: dir)
            try await pair.clone.run("branch", "--track", "local-feature", "origin/feature")
            try await pair.clone.run("branch", "plain")
            try await pair.origin.run("checkout", "-q", "feature")
            try pair.origin.write("feature-remote.txt", "f\n")
            try await pair.origin.commit("feature remote work")
            try await pair.origin.run("checkout", "-q", "main")
            try pair.origin.write("main-remote.txt", "m\n")
            try await pair.origin.commit("main remote work")
            let harness = try await loaded(pair.clone.root, existing: true)

            let plain = try #require(harness.anyRow("plain")?.ref)
            harness.model.update(plain)
            #expect(harness.model.runningOperations == 0)

            let nonCurrent = BranchesPopupRef(
                kind: .local,
                name: "local-feature",
                shortName: "local-feature",
                upstream: "origin/feature",
                isCurrent: false
            )
            harness.model.update(nonCurrent)
            let featureTip = try await pair.origin.run("rev-parse", "feature").trimmingCharacters(in: .whitespacesAndNewlines)
            try await eventually {
                let tip = try? await harness.fixture.run("rev-parse", "local-feature")
                return tip?.trimmingCharacters(in: .whitespacesAndNewlines) == featureTip
            }
            #expect(harness.fixture.exists("feature-remote.txt") == false)

            let current = try #require(harness.anyRow("main")?.ref)
            harness.model.update(current)
            try await eventually { harness.fixture.exists("main-remote.txt") }
        }
    }

    @Test
    func updateFailuresAreReported() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)

            harness.model.update(ghostRef(.local, "obsolete", upstream: "noslash"))
            try await eventually { harness.manager.lastAlert?.title == "Failed to update 'obsolete'" }
            #expect(harness.manager.lastAlert?.message == "Invalid upstream branch 'noslash'")

            harness.model.update(ghostRef(.local, "obsolete", upstream: "nowhere/obsolete"))
            try await eventually { harness.manager.lastAlert?.message != "Invalid upstream branch 'noslash'" }
            #expect(harness.manager.lastAlert?.title == "Failed to update 'obsolete'")
        }
    }

    @Test
    func checkoutAndUpdateSwitchesToTheBranchAndFastForwardsIt() async throws {
        try await withTempDir { dir in
            let pair = try await makeClone(in: dir)
            try await pair.clone.run("branch", "--track", "feature", "origin/feature")
            try await pair.clone.run("branch", "plain")
            try await pair.origin.run("checkout", "-q", "feature")
            try pair.origin.write("feature-remote.txt", "f\n")
            try await pair.origin.commit("feature remote work")
            try await pair.origin.run("checkout", "-q", "main")
            let harness = try await loaded(pair.clone.root, existing: true)

            let plain = try #require(harness.anyRow("plain")?.ref)
            harness.model.checkoutAndUpdate(plain)
            #expect(harness.dismissals == 0)
            #expect(harness.model.runningOperations == 0)

            let feature = try #require(harness.anyRow("feature")?.ref)
            harness.model.checkoutAndUpdate(feature)

            #expect(harness.dismissals == 1)
            try await eventually {
                harness.manager.currentBranch?.name == "feature" && harness.fixture.exists("feature-remote.txt")
            }
        }
    }

    @Test(arguments: [false, true])
    func pullingARemoteBranchMergesOrRebasesLocalCommits(rebase: Bool) async throws {
        try await withTempDir { dir in
            let pair = try await makeClone(in: dir)
            try pair.clone.write("local.txt", "local\n")
            try await pair.clone.commit("local work")
            try pair.origin.write("remote.txt", "remote\n")
            try await pair.origin.commit("remote work")
            try await pair.clone.run("fetch", "-q", "origin")
            let harness = try await loaded(pair.clone.root, existing: true)
            let remoteMain = try #require(harness.model.remoteBranchRefs.first { $0.shortName == "origin/main" })
            let local = try #require(harness.anyRow("main")?.ref)

            harness.model.pull(local, rebase: rebase)
            #expect(harness.dismissals == 0)
            #expect(harness.model.runningOperations == 0)

            harness.model.pull(remoteMain, rebase: rebase)

            #expect(harness.dismissals == 1)
            try await eventually { harness.fixture.exists("remote.txt") && harness.fixture.exists("local.txt") }
            try await eventually { harness.model.runningOperations == 0 }
            let merges = try await harness.fixture.run("rev-list", "--merges", "--count", "HEAD")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(merges == (rebase ? "0" : "1"))
        }
    }

    @Test
    func pullFailuresAreReported() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)

            harness.model.pull(ghostRef(.remote, "origin/ghost"), rebase: false)

            try await eventually { harness.manager.lastAlert?.title == "Failed to pull 'origin/ghost'" }
            #expect(harness.dismissals == 1)
        }
    }

    @Test
    func pushingATagSendsItToTheChosenRemoteAndReportsFailures() async throws {
        try await withTempDir { dir in
            let pair = try await makeClone(in: dir)
            try await pair.clone.run("tag", "v9")
            let harness = try await loaded(pair.clone.root, existing: true)
            harness.model.toggleExpansion(.section(.tags))
            let tag = try #require(harness.refRow(.tag, "v9")?.ref)
            let local = try #require(harness.anyRow("main")?.ref)

            harness.model.pushTag(local, remote: "origin")
            #expect(harness.dismissals == 0)
            #expect(harness.model.runningOperations == 0)

            harness.model.pushTag(tag, remote: "nowhere")
            try await eventually { harness.manager.lastAlert?.title == "Failed to push tag 'v9'" }

            harness.model.pushTag(tag, remote: "origin")
            try await eventually { ((try? await pair.origin.run("tag")) ?? "").contains("v9") }
            #expect(harness.dismissals == 2)
        }
    }

    @Test
    func pushRoutesRemoteAndTagRefsToThePushSheet() async throws {
        try await withTempDir { dir in
            let pair = try await makeClone(in: dir)
            try await pair.clone.run("tag", "v9")
            let harness = try await loaded(pair.clone.root, existing: true)
            harness.model.toggleExpansion(.section(.tags))
            let remote = try #require(harness.model.remoteBranchRefs.first { $0.shortName == "origin/feature" })
            let tag = try #require(harness.refRow(.tag, "v9")?.ref)

            harness.model.push(remote)
            #expect(harness.manager.pushSheetIsPresented)
            #expect(harness.manager.operationBranch?.name == "origin/feature")

            harness.model.push(tag)
            #expect(harness.manager.pushSheetIsPresented)
            #expect(harness.manager.operationBranch == nil)
            #expect(harness.dismissals == 2)
        }
    }

    @Test
    func checkingOutLocalBranchesDismissesAndReportsFailures() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            let feature = try #require(harness.anyRow("feature")?.ref)

            harness.model.checkout(feature)

            #expect(harness.dismissals == 1)
            try await eventually { harness.manager.currentBranch?.name == "feature" }

            harness.model.checkout(ghostRef(.local, "ghost"))
            try await eventually { harness.manager.lastAlert?.title == "Failed to check out 'ghost'" }

            harness.model.checkout(ghostRef(.tag, "no-such-tag"))
            try await eventually { harness.manager.lastAlert?.title == "Failed to check out 'no-such-tag'" }
            #expect(harness.dismissals == 3)
        }
    }

    @Test
    func checkingOutARemoteBranchWithoutALocalCounterpartCreatesATrackingBranch() async throws {
        try await withTempDir { dir in
            let pair = try await makeClone(in: dir)
            let harness = try await loaded(pair.clone.root, existing: true)
            let remote = try #require(harness.model.remoteBranchRefs.first { $0.shortName == "origin/feature" })

            harness.model.checkout(remote)

            #expect(harness.dismissals == 1)
            try await eventually { harness.manager.currentBranch?.name == "feature" }
            #expect(await harness.upstream(of: "feature") == "origin/feature")
        }
    }

    @Test
    func checkingOutAnUpToDateTrackedBranchJustSwitchesToIt() async throws {
        try await withTempDir { dir in
            let pair = try await makeClone(in: dir)
            try await pair.clone.run("checkout", "-q", "-b", "feature", "--track", "origin/feature")
            try await pair.clone.run("checkout", "-q", "main")
            let harness = try await loaded(pair.clone.root, existing: true)
            harness.model.dialogs.checkoutRemoteLocalCommits = { _, _, _ in
                Issue.record("no local commits to decide about")
                return .cancel
            }
            let remote = try #require(harness.model.remoteBranchRefs.first { $0.shortName == "origin/feature" })

            harness.model.checkout(remote)

            try await eventually { harness.manager.currentBranch?.name == "feature" }
        }
    }

    @Test
    func checkoutRemoteWithLocalCommitsCanBeCancelledOrResetToTheRemote() async throws {
        try await withTempDir { dir in
            let pair = try await makeDivergedFeatureClone(in: dir)
            let harness = try await loaded(pair.clone.root, existing: true)
            let remote = try #require(harness.model.remoteBranchRefs.first { $0.shortName == "origin/feature" })
            var decision = BranchesPopupLocalCommitsDecision.cancel
            harness.model.dialogs.checkoutRemoteLocalCommits = { _, _, _ in decision }

            harness.model.checkout(remote)
            try await eventually { harness.model.runningOperations == 0 }
            #expect(harness.manager.currentBranch?.name == "main")
            #expect(harness.manager.lastAlert == nil)
            #expect(harness.dismissals == 1)

            decision = .drop
            harness.model.checkout(remote)

            try await eventually { harness.manager.currentBranch?.name == "feature" }
            try await eventually { harness.model.runningOperations == 0 }
            let local = try await harness.fixture.run("rev-parse", "feature").trimmingCharacters(in: .whitespacesAndNewlines)
            let upstream = try await harness.fixture.run("rev-parse", "origin/feature")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(local == upstream)
            #expect(harness.fixture.exists("local.txt") == false)
            #expect(harness.fixture.exists("remote.txt"))
        }
    }

    @Test
    func checkoutRemoteRebaseWithConflictsNotifiesAndLeavesTheRebaseRunning() async throws {
        try await withTempDir { dir in
            let pair = try await makeDivergedFeatureClone(in: dir, localFile: "a.txt", remoteFile: "a.txt")
            let harness = try await loaded(pair.clone.root, existing: true)
            harness.model.dialogs.checkoutRemoteLocalCommits = { _, _, _ in .rebase }
            let remote = try #require(harness.model.remoteBranchRefs.first { $0.shortName == "origin/feature" })

            harness.model.checkout(remote)

            try await eventually {
                harness.model.operationState.isRebasing
                    && harness.notifications.contains { $0.title == "Rebase stopped with conflicts" }
            }
            let notification = try #require(harness.notifications.first)
            #expect(notification.description.contains("'origin/feature'"))
            #expect(notification.actionTitle == "Resolve Conflicts…")
            notification.action()
            #expect(harness.conflictsOpened == 1)
        }
    }

    @Test
    func checkoutRemoteWithATrackingConflictValidatesTheChosenName() async throws {
        try await withTempDir { dir in
            let pair = try await makeClone(in: dir)
            try await pair.clone.run("checkout", "-q", "-b", "feature", "--track", "origin/main")
            try await pair.clone.run("checkout", "-q", "main")
            try await pair.clone.run("branch", "other")
            let harness = try await loaded(pair.clone.root, existing: true)
            let remote = try #require(harness.model.remoteBranchRefs.first { $0.shortName == "origin/feature" })
            var answer: String?
            harness.model.dialogs.checkoutRemoteName = { _, _ in answer }

            harness.model.checkout(remote)
            try await eventually { harness.model.runningOperations == 0 }
            #expect(harness.errors.isEmpty)
            #expect(harness.manager.currentBranch?.name == "main")

            answer = "bad name"
            harness.model.checkout(remote)
            try await eventually { harness.model.runningOperations == 0 }
            #expect(harness.errors == ["Invalid Branch Name"])
            #expect(harness.manager.currentBranch?.name == "main")

            answer = "other"
            harness.model.checkout(remote)
            try await eventually { harness.manager.currentBranch?.name == "other" }
            try await eventually { harness.model.runningOperations == 0 }
            let other = try await harness.fixture.run("rev-parse", "other").trimmingCharacters(in: .whitespacesAndNewlines)
            let remoteTip = try await harness.fixture.run("rev-parse", "origin/feature")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(other == remoteTip)
        }
    }

    @Test
    func checkoutRemoteIgnoresMalformedRefsAndReportsGitFailures() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)

            harness.model.checkout(BranchesPopupRef(
                kind: .remote,
                name: "x",
                shortName: "x",
                upstream: nil,
                isCurrent: false
            ))
            #expect(harness.dismissals == 0)
            #expect(harness.model.runningOperations == 0)

            harness.model.checkout(ghostRef(.remote, "origin/ghost"))
            try await eventually { harness.manager.lastAlert?.title == "Failed to check out 'origin/ghost'" }
            #expect(harness.dismissals == 1)
        }
    }

    @Test
    func workingTreeDiffAgainstTheCurrentBranchReportsNoDifferences() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            let main = try #require(harness.anyRow("main")?.ref)
            let before = DreamderHeadless.suppressedModals.filter { $0 == "No Differences" }.count

            harness.model.showWorkingTreeDiff(main)

            #expect(harness.dismissals == 1)
            try await eventually { DreamderHeadless.suppressedModals.filter { $0 == "No Differences" }.count > before }
        }
    }

    @Test
    func newWorktreeSuggestsASiblingPathAndAddsTheWorktree() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            let target = dir.appending(path: "wt-main")
            var suggestion: String?
            var blockedWhileAsking = false
            harness.model.dialogs.worktreePath = { suggested in
                suggestion = suggested
                blockedWhileAsking = harness.model.isBlockingInput
                return target.path(percentEncoded: false)
            }

            harness.model.perform(.newWorktree)

            #expect(URL(fileURLWithPath: suggestion ?? "").lastPathComponent == dir.lastPathComponent + "-worktree")
            #expect(blockedWhileAsking)
            #expect(harness.model.isBlockingInput == false)
            #expect(harness.dismissals == 1)
            try await eventually { harness.fixture.exists("wt-main/.git") }
        }
    }

    @Test
    func newWorktreeFromABranchNamesThePathAfterItAndChecksItOut() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            try await harness.fixture.run("branch", "team/nested")
            await harness.model.reload()
            let nested = try #require(harness.anyRow("team/nested")?.ref)
            let target = dir.appending(path: "wt-nested")
            var suggestion: String?
            harness.model.dialogs.worktreePath = { suggested in
                suggestion = suggested
                return target.path(percentEncoded: false)
            }

            harness.model.promptNewWorktree(from: nested)

            #expect(URL(fileURLWithPath: suggestion ?? "").lastPathComponent == dir.lastPathComponent + "-team-nested")
            try await eventually { harness.fixture.exists("wt-nested/.git") }
            try await eventually { harness.model.runningOperations == 0 }
            let worktree = GitMergeFixture(existing: target)
            let head = try await worktree.run("rev-parse", "--abbrev-ref", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(head == "team/nested")
        }
    }

    @Test
    func newWorktreeIsDroppedForCancelledOrEmptyPathsAndReportsGitFailures() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            var answer: String?
            harness.model.dialogs.worktreePath = { _ in answer }

            harness.model.promptNewWorktree(from: nil)
            answer = ""
            harness.model.promptNewWorktree(from: nil)
            #expect(harness.dismissals == 0)
            #expect(harness.model.runningOperations == 0)
            #expect(harness.model.isBlockingInput == false)

            answer = dir.path(percentEncoded: false)
            harness.model.promptNewWorktree(from: nil)
            #expect(harness.dismissals == 1)
            try await eventually { harness.manager.lastAlert?.title == "Failed to create worktree" }
        }
    }

    @Test
    func checkoutRevisionPromptPassesTheRevisionToGitAndDetachesHead() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            var prompt: (title: String, message: String, placeholder: String, initial: String)?
            var blockedWhileAsking = false
            harness.model.namePrompt = { title, message, placeholder, initial in
                prompt = (title: title, message: message, placeholder: placeholder, initial: initial)
                blockedWhileAsking = harness.model.isBlockingInput
                return "v1.0"
            }

            harness.model.perform(.checkoutRevision)

            #expect(prompt?.title == "Checkout Tag or Revision")
            #expect(prompt?.message == "Check out a tag or any revision as a detached HEAD.")
            #expect(prompt?.placeholder == "Tag or revision")
            #expect(prompt?.initial == "")
            #expect(blockedWhileAsking)
            #expect(harness.model.isBlockingInput == false)
            #expect(harness.dismissals == 1)
            try await eventually {
                (try? await harness.fixture.run("rev-parse", "--abbrev-ref", "HEAD"))?.hasPrefix("HEAD") == true
            }
        }
    }

    @Test
    func checkoutRevisionPromptCancelDoesNothingAndUnknownRevisionsAreReported() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            var answer: String?
            harness.model.namePrompt = { _, _, _, _ in answer }

            harness.model.promptCheckoutRevision()
            #expect(harness.dismissals == 0)
            #expect(harness.model.runningOperations == 0)

            answer = "no-such-revision"
            harness.model.promptCheckoutRevision()
            #expect(harness.dismissals == 1)
            try await eventually { harness.manager.lastAlert?.title == "Failed to check out 'no-such-revision'" }
        }
    }

    @Test
    func theLiveRevisionPromptIsAModalThatHeadlessModeDeclines() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            let before = DreamderHeadless.suppressedModals.filter { $0 == "Checkout Tag or Revision" }.count

            harness.model.promptCheckoutRevision()

            let after = DreamderHeadless.suppressedModals.filter { $0 == "Checkout Tag or Revision" }.count
            #expect(after > before)
            #expect(harness.dismissals == 0)
            #expect(harness.model.isBlockingInput == false)
        }
    }

    @Test
    func mergeRebaseAndCheckoutAndRebaseFailuresAreReported() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            let ghost = ghostRef(.local, "ghost")

            harness.model.merge(ghost)
            try await eventually { harness.manager.lastAlert?.title == "Failed to merge 'ghost'" }

            harness.model.rebaseCurrent(onto: ghost)
            try await eventually { harness.manager.lastAlert?.title == "Failed to rebase onto 'ghost'" }

            harness.model.checkoutAndRebase(ghost)
            try await eventually { harness.manager.lastAlert?.title == "Failed to check out 'ghost'" }
            #expect(harness.dismissals == 1)
            #expect(harness.manager.currentBranch?.name == "main")
        }
    }

    @Test
    func checkoutAndRebaseWithConflictsNotifiesAboutTheRebase() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            try await harness.fixture.run("checkout", "-q", "feature")
            try harness.fixture.write("a.txt", "feature side\n")
            try await harness.fixture.commit("feature edits a")
            try await harness.fixture.run("checkout", "-q", "main")
            try harness.fixture.write("a.txt", "main side\n")
            try await harness.fixture.commit("main edits a")
            await harness.model.reload()
            let feature = try #require(harness.anyRow("feature")?.ref)

            harness.model.checkoutAndRebase(feature)

            try await eventually {
                harness.model.operationState.isRebasing
                    && harness.notifications.contains { $0.title == "Rebase stopped with conflicts" }
            }
            let notification = try #require(harness.notifications.first)
            #expect(notification.description.contains("'main'"))
        }
    }

    @Test
    func deletionFailuresForBranchesAndTagsAreReported() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            let main = try #require(harness.anyRow("main")?.ref)

            harness.model.delete(main)
            try await eventually { harness.manager.lastAlert?.title == "Failed to delete branch 'main'" }
            #expect(try await harness.branches().contains("main"))

            harness.model.delete(ghostRef(.tag, "ghost-tag"))
            try await eventually { harness.manager.lastAlert?.title == "Failed to delete tag 'ghost-tag'" }
            #expect(harness.notifications.isEmpty)
        }
    }

    @Test
    func decliningTheForceDeleteKeepsTheUnmergedBranch() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            try await harness.fixture.run("checkout", "-q", "-b", "unmerged")
            try harness.fixture.write("u.txt", "u\n")
            try await harness.fixture.commit("unmerged work")
            try await harness.fixture.run("checkout", "-q", "main")
            await harness.model.reload()
            let unmerged = try #require(harness.anyRow("unmerged")?.ref)
            var asked = 0
            var blockedWhileAsking = false
            harness.model.dialogs.unmergedDelete = { _, _ in
                asked += 1
                blockedWhileAsking = harness.model.isBlockingInput
                return .cancel
            }

            harness.model.delete(unmerged)

            try await eventually { asked == 1 && harness.model.runningOperations == 0 }
            #expect(blockedWhileAsking)
            #expect(harness.model.isBlockingInput == false)
            #expect(try await harness.branches().contains("unmerged"))
            #expect(harness.notifications.isEmpty)
            #expect(harness.manager.lastAlert == nil)
        }
    }

    @Test
    func restoringADeletedBranchOrTagThatWasRecreatedReportsTheFailure() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            harness.model.toggleExpansion(.section(.tags))
            let obsolete = try #require(harness.anyRow("obsolete")?.ref)
            let tag = try #require(harness.refRow(.tag, "v1.0")?.ref)

            harness.model.delete(obsolete)
            try await eventually { harness.notifications.contains { $0.title == "Deleted Branch: obsolete" } }
            try await harness.fixture.run("branch", "obsolete")
            let branchRestore = try #require(harness.notifications.first { $0.title == "Deleted Branch: obsolete" })
            #expect(harness.manager.lastAlert == nil)
            branchRestore.action()
            try await eventually { harness.manager.lastAlert?.title == "Failed to restore branch 'obsolete'" }

            harness.model.delete(tag)
            try await eventually { harness.notifications.contains { $0.title == "Deleted Tag: v1.0" } }
            try await harness.fixture.run("tag", "v1.0")
            let tagRestore = try #require(harness.notifications.first { $0.title == "Deleted Tag: v1.0" })
            tagRestore.action()
            try await eventually { harness.manager.lastAlert?.title == "Failed to restore tag 'v1.0'" }
        }
    }

    @Test
    func deletingARemoteBranchAsksAgainAboutTrackingBranchesAndKeepsThemWhenDeclined() async throws {
        try await withTempDir { dir in
            let pair = try await makeClone(in: dir)
            try await pair.clone.run("branch", "--track", "feature", "origin/feature")
            let harness = try await loaded(pair.clone.root, existing: true)
            var titles: [String] = []
            var messages: [String] = []
            harness.model.dialogs.confirm = { title, message, _ in
                titles.append(title)
                messages.append(message)
                return title == "Delete Remote Branch"
            }
            let remote = try #require(harness.model.remoteBranchRefs.first { $0.shortName == "origin/feature" })

            harness.model.delete(remote)

            #expect(titles == ["Delete Remote Branch", "Delete Tracking Branches"])
            #expect(messages.first == "Delete 'origin/feature' from remote 'origin'?\n\nLocal tracking branches: feature")
            #expect(harness.model.isBlockingInput == false)
            try await eventually {
                (try? await pair.origin.run("branch", "--format=%(refname:short)"))?.contains("feature") == false
            }
            try await eventually { harness.model.runningOperations == 0 }
            #expect(try await harness.branches().contains("feature"))
        }
    }

    @Test
    func deletingARemoteBranchIsCancelledByTheFirstConfirmationAndIgnoresMalformedRefs() async throws {
        try await withTempDir { dir in
            let pair = try await makeClone(in: dir)
            let harness = try await loaded(pair.clone.root, existing: true)
            var titles: [String] = []
            harness.model.dialogs.confirm = { title, _, _ in
                titles.append(title)
                return false
            }
            let remote = try #require(harness.model.remoteBranchRefs.first { $0.shortName == "origin/feature" })

            harness.model.delete(remote)
            harness.model.delete(BranchesPopupRef(kind: .remote, name: "x", shortName: "x", upstream: nil, isCurrent: false))

            #expect(titles == ["Delete Remote Branch"])
            #expect(harness.model.runningOperations == 0)
            let originBranches = try await pair.origin.run("branch", "--format=%(refname:short)")
            #expect(originBranches.contains("feature"))
        }
    }

    @Test
    func deletingARemoteBranchThatCannotBePushedReportsTheFailure() async throws {
        try await withTempDir { dir in
            let pair = try await makeClone(in: dir)
            let harness = try await loaded(pair.clone.root, existing: true)
            harness.model.dialogs.confirm = { _, _, _ in true }
            let remote = try #require(harness.model.remoteBranchRefs.first { $0.shortName == "origin/feature" })
            let missing = dir.appending(path: "missing").path(percentEncoded: false)
            try await pair.clone.run("remote", "set-url", "origin", missing)

            harness.model.delete(remote)

            try await eventually { harness.manager.lastAlert?.title == "Failed to delete remote branch 'origin/feature'" }
        }
    }

    @Test
    func trackingBranchChangeFailuresAreReportedAndTheTreeRefreshed() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            let obsolete = try #require(harness.anyRow("obsolete")?.ref)

            harness.model.setUpstream(obsolete, to: "nowhere/obsolete")

            try await eventually { harness.manager.lastAlert?.title == "Failed to change the tracked branch" }
            #expect(await harness.upstream(of: "obsolete") == nil)
            #expect(harness.anyRow("obsolete") != nil)
        }
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct BranchesPopupDefaultPresenterTests {
    private let pooledDefaults: PooledDefaults
    private var defaults: UserDefaults { pooledDefaults.defaults }

    init() throws {
        pooledDefaults = try PooledDefaults()
    }

    private func makeModel(in dir: URL) async throws -> (model: BranchesPopupViewModel, workspace: WorkspaceDocument) {
        let fixture = try await GitMergeFixture(root: dir)
        try fixture.write("a.txt", "a\n")
        try await fixture.commit("initial")
        let workspace = try HostedViewFixture.makeWorkspace(in: dir)
        let manager = try #require(workspace.sourceControlManager)
        let model = BranchesPopupViewModel(
            sourceControlManager: manager,
            workspace: workspace,
            defaults: defaults,
            dismiss: {}
        )
        return (model, workspace)
    }

    private func compareWindows(titled title: String) -> [NSWindow] {
        NSApp.windows.filter { $0.title == title && $0.isVisible }
    }

    @Test
    func comparingOpensTheCompareWindowForTheBranchPair() async throws {
        try await withTempDir { dir in
            let (model, workspace) = try await makeModel(in: dir)
            defer { workspace.close() }
            await model.reload()
            let topic = "topic-\(UUID().uuidString)"
            let title = "Comparing \(topic) with main"
            defer { compareWindows(titled: title).forEach { $0.close() } }
            let ref = BranchesPopupRef(kind: .local, name: topic, shortName: topic, upstream: nil, isCurrent: false)

            model.compareWithCurrent(ref)

            try await eventually { compareWindows(titled: title).count == 1 }
        }
    }
}
