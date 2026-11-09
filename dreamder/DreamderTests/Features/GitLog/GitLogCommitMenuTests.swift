import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct GitLogCommitMenuTests {
    @MainActor
    private struct TableSession {
        let rig: GitLogCommitActionsRig
        let hosted: HostedView
        let input: GitToolWindowCovInput

        func rowPoint(_ subject: String) throws -> CGPoint {
            let index = try #require(rig.model.visibleCommits.firstIndex { $0.subject == subject })
            let height = Islands.listRowHeight
            return CGPoint(x: 120, y: 4 + CGFloat(index) * height + height / 2)
        }

        func menu(_ subject: String) throws -> NSMenu {
            try input.contextMenu(at: try rowPoint(subject))
        }

        func close() {
            hosted.close()
            rig.close()
        }
    }

    private func makeSession(
        _ directory: URL,
        scenario: GitLogCommitActionsRig.Scenario = .history
    ) async throws -> TableSession {
        let rig = try await GitLogCommitActionsRig.make(in: directory, scenario: scenario)
        let model = rig.model
        let seams = rig.recorder.seams()
        let hosted = try HostedViewFixture.hostInWorkspace(rig.workspace, size: NSSize(width: 700, height: 300)) {
            GitLogCommitTable(viewModel: model)
                .environment(\.gitLogCommitSeams, seams)
        }
        let input = GitToolWindowCovInput(hosted: hosted)
        try await hosted.settle(.milliseconds(400))
        return TableSession(rig: rig, hosted: hosted, input: input)
    }

    private func titles(of menu: NSMenu) -> [String] {
        menu.items.filter { !$0.isSeparatorItem }.map(\.title)
    }

    private func perform(_ title: String, in menu: NSMenu) throws {
        let index = try #require(menu.items.firstIndex { $0.title == title })
        menu.performActionForItem(at: index)
    }

    private func checkoutSubmenu(_ session: TableSession, _ subject: String) throws -> NSMenu {
        let item = try #require(try session.menu(subject).items.first { $0.title == "Checkout" })
        return try #require(item.submenu)
    }

    private func menu(in hosted: HostedView, at point: CGPoint) -> NSMenu? {
        let hosting = hosted.hosting
        let local = hosting.isFlipped
            ? NSPoint(x: point.x, y: point.y)
            : NSPoint(x: point.x, y: hosting.bounds.height - point.y)
        let event = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: hosting.convert(local, to: nil),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: hosted.window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
        return event.flatMap { hosting.menu(for: $0) }
    }

    private func probeCommitMenu(in hosted: HostedView) -> NSMenu? {
        var y: CGFloat = 60
        while y < 400 {
            if let candidate = menu(in: hosted, at: CGPoint(x: 420, y: y)),
               candidate.items.contains(where: { $0.title == "New Tag…" }) {
                return candidate
            }
            y += 4
        }
        return nil
    }

    @Test
    func commitMenuListsTheActionsAndSplitsCheckoutWhenTheCommitHasLocalBranches() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(directory)
            defer { session.close() }
            let head = try session.rig.commit("Main work")
            let feature = try session.rig.commit("Feature work")

            let headMenu = try session.menu("Main work")
            #expect(titles(of: headMenu) == [
                "Copy Revision Number",
                "Cherry-Pick",
                "Checkout Revision '\(head.shortHash)'",
                "New Branch…",
                "New Tag…"
            ])
            #expect(headMenu.items.filter(\.isSeparatorItem).count == 2)

            let featureMenu = try session.menu("Feature work")
            #expect(titles(of: featureMenu) == [
                "Copy Revision Number",
                "Cherry-Pick",
                "Checkout",
                "New Branch…",
                "New Tag…"
            ])
            #expect(
                try checkoutSubmenu(session, "Feature work").items.map(\.title)
                    == ["feature", "Revision '\(feature.shortHash)'"]
            )
        }
    }

    @Test
    func copyRevisionNumberItemCopiesTheHashAndSelectsTheRow() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(directory)
            defer { session.close() }
            let target = try session.rig.commit("Feature work")

            try perform("Copy Revision Number", in: try session.menu("Feature work"))

            try await eventually { session.rig.recorder.copied == [target.hash] }
            #expect(session.rig.model.selectedHash == target.hash)
        }
    }

    @Test
    func newTagItemCreatesTheTagOnTheCommit() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(directory)
            defer { session.close() }
            let target = try session.rig.commit("Feature work")
            session.rig.recorder.tagAnswer = GitLogTagResult(name: "menu-tag", message: "annotated", force: false)

            try perform("New Tag…", in: try session.menu("Feature work"))

            try await eventually {
                (try? await session.rig.fixture.run("rev-parse", "menu-tag^{commit}"))?
                    .trimmingCharacters(in: .whitespacesAndNewlines) == target.hash
            }
            #expect(try await session.rig.fixture.run("cat-file", "-t", "menu-tag").hasPrefix("tag"))
        }
    }

    @Test
    func newBranchItemCreatesAndChecksOutTheBranchAtTheCommit() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(directory)
            defer { session.close() }
            let target = try session.rig.commit("Feature work")
            session.rig.recorder.branchAnswer = BranchesPopupBranchDialogResult(name: "from-menu")

            try perform("New Branch…", in: try session.menu("Feature work"))

            try await eventually { try await session.rig.currentBranchName() == "from-menu" }
            #expect(try await session.rig.head() == target.hash)
        }
    }

    @Test
    func cherryPickItemAppliesTheCommit() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(directory)
            defer { session.close() }

            try perform("Cherry-Pick", in: try session.menu("Feature work"))

            try await eventually { session.rig.fixture.exists("f.txt") }
            try await eventually { session.rig.recorder.notifications.first?.title == "Cherry-pick successful" }
            #expect(try await session.rig.fixture.run("log", "-1", "--format=%s").hasPrefix("Feature work"))
        }
    }

    @Test
    func cherryPickItemWithConflictsPresentsTheMergeTool() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(directory, scenario: .conflict)
            defer { session.close() }

            try perform("Cherry-Pick", in: try session.menu("Feature work"))

            try await eventually { session.rig.recorder.presented.count == 1 }
            #expect(try await session.rig.fixture.unmergedPaths() == ["src/main.swift"])
            #expect(session.rig.recorder.notifications.first?.title == "Cherry-pick was performed with conflicts")
            #expect(MergeConflictsCenter.shared.entries(for: session.rig.manager.workspaceURL).isEmpty == false)
        }
    }

    @Test
    func checkoutRevisionItemDetachesHead() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(directory)
            defer { session.close() }
            let initial = try session.rig.commit("initial")

            try perform("Checkout Revision '\(initial.shortHash)'", in: try session.menu("initial"))

            try await eventually { try await session.rig.currentBranchName() == "HEAD" }
            #expect(try await session.rig.head() == initial.hash)
        }
    }

    @Test
    func checkoutSubmenuBranchItemSwitchesToTheLocalBranch() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(directory)
            defer { session.close() }

            try perform("feature", in: try checkoutSubmenu(session, "Feature work"))

            try await eventually { try await session.rig.currentBranchName() == "feature" }
        }
    }

    @Test
    func checkoutSubmenuRevisionItemDetachesHead() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(directory)
            defer { session.close() }
            let feature = try session.rig.commit("Feature work")

            try perform("Revision '\(feature.shortHash)'", in: try checkoutSubmenu(session, "Feature work"))

            try await eventually { try await session.rig.currentBranchName() == "HEAD" }
            #expect(try await session.rig.head() == feature.hash)
        }
    }

    @Test
    func rowWithoutSourceControlEnvironmentHasNoMenuItems() async throws {
        let commit = GitLogCommit(
            hash: "0123456789abcdef0123456789abcdef01234567",
            parents: [],
            authorName: "A",
            authorEmail: "a@b.c",
            date: Date(),
            refs: [],
            subject: "Lonely"
        )
        let hosted = HostedViewFixture.host(size: NSSize(width: 400, height: 80)) {
            GitLogCommitRow(commit: commit, graphRow: nil, laneCount: 1, isSelected: false) {}
        }
        defer { hosted.close() }
        _ = GitToolWindowCovInput(hosted: hosted)
        try await hosted.settle(.milliseconds(100))

        let found = menu(in: hosted, at: CGPoint(x: 120, y: Islands.listRowHeight / 2))

        #expect(found?.items.filter { !$0.isSeparatorItem }.isEmpty ?? true)
    }

    @Test
    func gitToolWindowWiresTheCommitMenuToTheRepository() async throws {
        try await withTempDir { directory in
            let rig = try await GitLogCommitActionsRig.make(in: directory)
            defer { rig.close() }
            let seams = rig.recorder.seams()
            let model = GitToolWindowModel()
            let hosted = try HostedViewFixture.hostInWorkspace(rig.workspace, size: NSSize(width: 1000, height: 600)) {
                GitToolWindow(model: model)
                    .environment(\.gitLogCommitSeams, seams)
            }
            defer { hosted.close() }
            _ = GitToolWindowCovInput(hosted: hosted)
            try await eventually { rig.manager.currentBranch != nil }
            try await eventually {
                !model.logModel.isLoading && !model.logModel.visibleCommits.isEmpty
            }
            try await hosted.settle(.milliseconds(800))
            rig.recorder.tagAnswer = GitLogTagResult(name: "window-tag", message: "", force: false)

            let menu = try #require(probeCommitMenu(in: hosted))
            try perform("New Tag…", in: menu)

            try await eventually {
                (try? await rig.fixture.run("tag"))?.contains("window-tag") == true
            }
            #expect(rig.recorder.tagRequests.count == 1)
        }
    }
}
