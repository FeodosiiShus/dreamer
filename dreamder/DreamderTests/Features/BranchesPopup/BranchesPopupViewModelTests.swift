import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite
struct BranchesPopupViewModelTests {
    private final class Registry {
        var harnesses: [Harness] = []
    }

    private let defaults = UserDefaults(suiteName: "dreamder.tests.branches.\(UUID().uuidString)") ?? .standard
    private let registry = Registry()

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

        func branches() throws -> [String] {
            try fixture.run("branch", "--format=%(refname:short)")
                .split(separator: "\n")
                .map(String.init)
                .sorted()
        }

        func upstream(of branch: String) -> String? {
            let output = try? fixture.run("rev-parse", "--abbrev-ref", "\(branch)@{upstream}")
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
        let fixture = try await GitMergeFixture.offMain {
            guard !existing else { return GitMergeFixture(existing: dir) }
            let fixture = try GitMergeFixture(root: dir)
            try fixture.write("a.txt", "a\n")
            try fixture.commit("initial")
            try fixture.run("tag", "v1.0")
            try fixture.run("checkout", "-q", "-b", "feature")
            try fixture.write("feature.txt", "feature\n")
            try fixture.commit("feature work")
            try fixture.run("checkout", "-q", "main")
            try fixture.run("branch", "obsolete")
            return fixture
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
                try harness.fixture.run("branch", "b\(number)")
                try harness.fixture.run("checkout", "-q", "b\(number)")
            }
            try harness.fixture.run("checkout", "-q", "main")
            try harness.fixture.run("branch", "-D", "b6")
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
                (try? harness.fixture.run("rev-parse", "--abbrev-ref", "HEAD"))?.hasPrefix("HEAD") == true
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

            try harness.fixture.run("reset", "-q", "--hard", "HEAD~1")
            #expect(harness.fixture.exists("feature.txt") == false)
            harness.model.rebaseCurrent(onto: feature)
            try await eventually { harness.fixture.exists("feature.txt") }
            #expect(try harness.fixture.run("rev-parse", "--abbrev-ref", "HEAD").hasPrefix("main"))
        }
    }

    @Test
    func checkoutAndRebaseReplaysTheBranchOnCurrent() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            try harness.fixture.write("main.txt", "main\n")
            try harness.fixture.commit("main work")
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
            try harness.fixture.run("checkout", "-q", "feature")
            try harness.fixture.write("a.txt", "feature side\n")
            try harness.fixture.commit("feature edits a")
            try harness.fixture.run("checkout", "-q", "main")
            try harness.fixture.write("a.txt", "main side\n")
            try harness.fixture.commit("main edits a")
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
            try harness.fixture.run("merge", "--abort")
            await harness.model.reload()
            #expect(harness.model.operationState == .none)
        }
    }

    @Test
    func ongoingRebaseActionsAreListedAndAbortWorks() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            try harness.fixture.run("checkout", "-q", "feature")
            try harness.fixture.write("a.txt", "feature side\n")
            try harness.fixture.commit("feature edits a")
            try harness.fixture.run("checkout", "-q", "main")
            try harness.fixture.write("a.txt", "main side\n")
            try harness.fixture.commit("main edits a")
            try harness.fixture.run("checkout", "-q", "feature")
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
            try await eventually { (try? harness.branches())?.contains("created") == true }
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
            let featureTip = try harness.fixture.run("rev-parse", "feature")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let feature = try #require(harness.anyRow("feature")?.ref)

            harness.model.promptNewBranch(from: feature)

            try await eventually {
                let tip = try? harness.fixture.run("rev-parse", "obsolete")
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
            #expect(try harness.branches().contains("bad name") == false)
        }
    }

    @Test
    func renameDialogOffersUnsetUpstream() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            try harness.fixture.run("branch", "--set-upstream-to=main", "obsolete")
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
                (try? harness.branches())?.contains("renamed") == true && harness.upstream(of: "renamed") == nil
            }
            #expect(try harness.branches().contains("obsolete") == false)
        }
    }

    @Test
    func deletingUnmergedBranchRequiresForceAndCanBeRestored() async throws {
        try await withTempDir { dir in
            let harness = try await loaded(dir)
            try harness.fixture.run("checkout", "-q", "-b", "unmerged")
            try harness.fixture.write("u.txt", "u\n")
            try harness.fixture.commit("unmerged work")
            try harness.fixture.run("checkout", "-q", "main")
            await harness.model.reload()
            let unmerged = try #require(harness.anyRow("unmerged")?.ref)
            harness.model.dialogs.unmergedDelete = { name, commits in
                #expect(name == "unmerged")
                #expect(commits.isEmpty == false)
                return .force
            }

            harness.model.delete(unmerged)

            try await eventually { (try? harness.branches())?.contains("unmerged") == false }
            #expect(harness.manager.lastAlert == nil)
            try await eventually { harness.notifications.contains { $0.title == "Deleted Branch: unmerged" } }
            let notification = try #require(harness.notifications.first { $0.title == "Deleted Branch: unmerged" })
            #expect(notification.actionTitle == "Restore")

            notification.action()
            try await eventually { (try? harness.branches())?.contains("unmerged") == true }
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

            try await eventually { (try? harness.branches())?.contains("obsolete") == false }
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
                ((try? harness.fixture.run("tag")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            try await eventually { harness.notifications.contains { $0.title == "Deleted Tag: v1.0" } }
            let notification = try #require(harness.notifications.first { $0.title == "Deleted Tag: v1.0" })
            notification.action()
            try await eventually { ((try? harness.fixture.run("tag")) ?? "").contains("v1.0") }
        }
    }

    @Test
    func deletingRemoteBranchCanAlsoDeleteTrackingBranches() async throws {
        try await withTempDir { dir in
            let originRoot = dir.appending(path: "origin")
            try FileManager.default.createDirectory(at: originRoot, withIntermediateDirectories: true)
            let origin = try GitMergeFixture(root: originRoot)
            try origin.write("a.txt", "one\n")
            try origin.commit("initial")
            try origin.run("branch", "doomed")

            let cloneRoot = dir.appending(path: "clone")
            try origin.run(
                "clone",
                "-q",
                origin.root.path(percentEncoded: false),
                cloneRoot.path(percentEncoded: false)
            )
            let cloneFixture = GitMergeFixture(existing: cloneRoot)
            try cloneFixture.run("config", "user.email", "clone@dreamder.test")
            try cloneFixture.run("config", "user.name", "Clone")
            try cloneFixture.run("branch", "--track", "doomed", "origin/doomed")

            let harness = try await loaded(cloneRoot, existing: true)
            harness.model.dialogs.confirm = { title, _, _ in
                title == "Delete Remote Branch" || title == "Delete Tracking Branches"
            }
            let doomed = try #require(harness.model.remoteBranchRefs.first { $0.shortName == "origin/doomed" })
            #expect(doomed.kind == .remote)

            harness.model.delete(doomed)

            try await eventually {
                (try? origin.run("branch", "--format=%(refname:short)"))?.contains("doomed") == false
            }
            try await eventually { (try? harness.branches())?.contains("doomed") == false }
        }
    }

    @Test
    func checkoutRemoteWithLocalCommitsUsesInjectedDecision() async throws {
        try await withTempDir { dir in
            let originRoot = dir.appending(path: "origin")
            try FileManager.default.createDirectory(at: originRoot, withIntermediateDirectories: true)
            let origin = try GitMergeFixture(root: originRoot)
            try origin.write("a.txt", "base\n")
            try origin.commit("initial")
            try origin.run("branch", "feature")

            let cloneRoot = dir.appending(path: "clone")
            try origin.run(
                "clone",
                "-q",
                origin.root.path(percentEncoded: false),
                cloneRoot.path(percentEncoded: false)
            )
            let cloneFixture = GitMergeFixture(existing: cloneRoot)
            try cloneFixture.run("config", "user.email", "clone@dreamder.test")
            try cloneFixture.run("config", "user.name", "Clone")
            try cloneFixture.run("checkout", "-q", "-b", "feature", "--track", "origin/feature")
            try cloneFixture.write("local.txt", "local\n")
            try cloneFixture.commit("local work")
            try origin.run("checkout", "-q", "feature")
            try origin.write("remote.txt", "remote\n")
            try origin.commit("remote work")
            try cloneFixture.run("fetch", "-q", "origin")

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
            let origin = try GitMergeFixture(root: originRoot)
            try origin.write("a.txt", "base\n")
            try origin.commit("initial")
            try origin.run("branch", "feature")

            let cloneRoot = dir.appending(path: "clone")
            try origin.run(
                "clone",
                "-q",
                origin.root.path(percentEncoded: false),
                cloneRoot.path(percentEncoded: false)
            )
            let cloneFixture = GitMergeFixture(existing: cloneRoot)
            try cloneFixture.run("config", "user.email", "clone@dreamder.test")
            try cloneFixture.run("config", "user.name", "Clone")
            try cloneFixture.run("checkout", "-q", "-b", "feature", "--track", "origin/main")
            try cloneFixture.run("checkout", "-q", "main")

            let harness = try await loaded(cloneRoot, existing: true)
            harness.model.dialogs.checkoutRemoteName = { remote, suggested in
                #expect(remote == "origin/feature")
                #expect(suggested == "feature")
                return "feature-local"
            }
            let remote = try #require(harness.anyRow("origin/feature")?.ref)

            harness.model.checkout(remote)

            try await eventually { harness.manager.currentBranch?.name == "feature-local" }
            #expect(harness.upstream(of: "feature-local") == "origin/feature")
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
            try harness.fixture.run("branch", "alpha")
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
            try await eventually { harness.upstream(of: "obsolete") == "main" }

            harness.model.setUpstream(obsolete, to: nil)
            try await eventually { harness.upstream(of: "obsolete") == nil }
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
            try harness.fixture.run("branch", "team/nested")
            await harness.model.reload()
            harness.model.showsRecentBranches = false
            harness.model.groupsByDirectory = true
            #expect(harness.model.sections.first { $0.id == .local }?.nodes.contains { $0.kind == .group } == true)

            harness.model.groupsByDirectory = false
            #expect(harness.model.sections.first { $0.id == .local }?.nodes.contains { $0.kind == .group } == false)
        }
    }
}
