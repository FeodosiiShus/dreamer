import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Observable
private final class GitPaneDividerWidthBox {
    var width: CGFloat

    init(width: CGFloat) {
        self.width = width
    }
}

@MainActor
@Suite(.uiGate)
struct GitToolWindowCoverage {
    private static let windowSize = NSSize(width: 900, height: 600)

    @MainActor
    private struct Session {
        let workspace: WorkspaceDocument
        let manager: SourceControlManager
        let model: GitToolWindowModel
        let hosted: HostedView

        func close() {
            hosted.close()
            workspace.close()
        }
    }

    private func makeSession(_ directory: URL) async throws -> Session {
        let workspace = try HostedViewFixture.makeWorkspace(in: directory)
        let manager = try #require(workspace.sourceControlManager)
        let model = GitToolWindowModel()
        let hosted = try HostedViewFixture.hostInWorkspace(workspace, size: Self.windowSize) {
            GitToolWindow(model: model)
        }
        return Session(workspace: workspace, manager: manager, model: model, hosted: hosted)
    }

    @Test
    func directoryWithoutRepositoryShowsThePlaceholderAndRefreshKeepsItEmpty() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(directory)
            defer { session.close() }
            try await session.hosted.settle(.milliseconds(400))
            #expect(session.manager.isGitRepository == false)
            #expect(session.hosted.renders())

            await session.model.refresh(manager: session.manager)
            try await session.hosted.settle(.milliseconds(300))

            #expect(session.manager.currentBranch == nil)
            #expect(session.model.logModel.commits.isEmpty)
            #expect(session.model.logModel.errorMessage != nil)
            #expect(session.hosted.renders())
        }
    }

    @Test
    func repositoryWithHistoryLoadsAndFollowsRepositoryAndBranchChanges() async throws {
        try await withTempDir { directory in
            _ = try await GitToolWindowCovRepo.make(in: directory)
            let session = try await makeSession(directory)
            defer { session.close() }
            try await eventually { session.manager.currentBranch != nil }
            try await session.hosted.settle(.milliseconds(800))
            let loaded = session.hosted.snapshot()
            #expect(session.hosted.renders())

            session.manager.isGitRepository = false
            try await session.hosted.settle(.milliseconds(300))
            let placeholder = session.hosted.snapshot()
            #expect(HostedView.pixelsDiffer(loaded, placeholder))

            session.manager.currentBranch = nil
            try await session.hosted.settle(.milliseconds(300))
            #expect(session.manager.currentBranch == nil)

            session.manager.isGitRepository = true
            try await eventually { session.manager.currentBranch != nil }
            try await session.hosted.settle(.milliseconds(800))
            #expect(HostedView.pixelsDiffer(placeholder, session.hosted.snapshot()))

            session.manager.currentBranch = nil
            try await session.hosted.settle(.milliseconds(500))
            #expect(session.hosted.renders())
        }
    }

    @Test
    func refreshReloadsBranchesAndTheLog() async throws {
        try await withTempDir { directory in
            _ = try await GitToolWindowCovRepo.make(in: directory)
            let session = try await makeSession(directory)
            defer { session.close() }
            try await eventually { session.manager.currentBranch != nil }
            try await eventually { !session.model.logModel.commits.isEmpty }

            session.manager.branches = []
            await session.model.refresh(manager: session.manager)

            #expect(!session.manager.branches.isEmpty)
            #expect(session.manager.currentBranch?.name == "main")
            #expect(session.model.logModel.commits.contains { $0.subject == "Remove guide" })
        }
    }

    @Test
    func consoleTabSwitchesTheContentAndClosingItDismissesTheLog() async throws {
        try await withTempDir { directory in
            _ = try await GitToolWindowCovRepo.make(in: directory)
            let session = try await makeSession(directory)
            defer { session.close() }
            let log = GitConsoleLog.log(for: session.manager.repositoryURL)
            log.record(
                command: "push origin main",
                directory: session.manager.repositoryURL,
                output: "error: failed to push some refs\nhint: Updates were rejected\nplain line"
            )
            log.record(
                command: "commit -m message",
                directory: session.manager.repositoryURL,
                output: ""
            )
            try await eventually { session.manager.currentBranch != nil }
            try await session.hosted.settle(.milliseconds(800))
            let logContent = session.hosted.snapshot()
            #expect(log.entries.count >= 2)
            #expect(log.isDismissed == false)

            let tab = GitConsoleTab(log: log, isSelected: session.model.consoleSelection)
            tab.select()
            try await session.hosted.settle(.milliseconds(300))

            #expect(session.model.pane == .console)
            #expect(HostedView.pixelsDiffer(logContent, session.hosted.snapshot()))

            tab.dismiss()
            try await session.hosted.settle(.milliseconds(300))

            #expect(log.isDismissed)
            #expect(session.model.pane == .log)
            #expect(session.hosted.renders())
        }
    }

    @Test
    func emptyRepositoryShowsAnEmptyLog() async throws {
        try await withTempDir { directory in
            _ = try await GitMergeFixture(root: directory)
            let session = try await makeSession(directory)
            defer { session.close() }
            #expect(session.manager.isGitRepository)

            try await session.hosted.settle(.milliseconds(1_000))

            #expect(session.hosted.renders())
        }
    }

    @Test
    func dividerRendersAsAThinSeparatorForBothOrientations() async throws {
        for inverted in [false, true] {
            let hosted = HostedViewFixture.host(size: NSSize(width: 200, height: 100)) {
                GitPaneDivider(width: .constant(200), range: 100...300, inverted: inverted)
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))
            #expect(hosted.snapshot() != nil)
        }
    }

    @Test
    func dividerShowsTheResizeCursorOnlyWhileHovering() {
        #expect(GitPaneDivider.cursor(isHovering: true) == NSCursor.resizeLeftRight)
        #expect(GitPaneDivider.cursor(isHovering: false) == NSCursor.arrow)
    }

    @Test
    func dividerHoverAppliesTheResizeCursorAndLeavingRestoresTheArrow() {
        let divider = GitPaneDivider(width: .constant(200), range: 100...300)

        divider.hover(true)
        #expect(NSCursor.current == NSCursor.resizeLeftRight)

        divider.hover(false)
        #expect(NSCursor.current == NSCursor.arrow)
    }

    @Test
    func dividerDragMovesTheBoundWidthAndClampsToTheRange() {
        let box = GitPaneDividerWidthBox(width: 200)
        let divider = GitPaneDivider(width: Bindable(box).width, range: 100...300)

        divider.dragChanged(CGSize(width: 40, height: 7))
        #expect(box.width == 240)

        divider.dragChanged(CGSize(width: 1000, height: 0))
        #expect(box.width == 300)

        divider.dragEnded()
        divider.dragChanged(CGSize(width: -50, height: 0))
        #expect(box.width == 250)

        let inverted = GitPaneDivider(width: Bindable(box).width, range: 100...300, inverted: true)
        inverted.dragChanged(CGSize(width: 1000, height: 0))
        #expect(box.width == 100)
    }

    @Test
    func headerActionsRefreshTheBranchesAndHideTheWindow() async throws {
        try await withTempDir { directory in
            _ = try await GitToolWindowCovRepo.make(in: directory)
            let session = try await makeSession(directory)
            defer { session.close() }
            try await eventually { session.manager.currentBranch != nil }
            let toolWindows = session.workspace.toolWindowManager
            let actions = GitToolWindowActions(
                model: session.model,
                manager: session.manager,
                toolWindows: toolWindows
            )

            session.manager.branches = []
            actions.startRefresh()
            try await eventually { !session.manager.branches.isEmpty }
            try await eventually { session.model.logModel.commits.contains { $0.subject == "Remove guide" } }

            toolWindows.show(.git)
            #expect(toolWindows.isVisible(.git))
            actions.hide()
            #expect(!toolWindows.isVisible(.git))
        }
    }
}

@MainActor
@Suite(.uiGate)
struct GitToolWindowModelTests {
    @Test
    func startsOnTheLogWithTheDefaultPaneWidths() {
        let model = GitToolWindowModel()

        #expect(model.pane == .log)
        #expect(model.showsConsole == false)
        #expect(model.branchesWidth == 210)
        #expect(model.detailsWidth == 320)
    }

    @Test
    func tabsSwitchBetweenLogConsoleAndShelf() {
        let model = GitToolWindowModel()

        model.showShelf()
        #expect(model.pane == .shelf)

        model.setConsoleSelected(true)
        #expect(model.pane == .console)
        #expect(model.showsConsole)

        model.showShelf()
        #expect(model.pane == .shelf)
        #expect(model.showsConsole == false)

        model.showLog()
        #expect(model.pane == .log)
    }

    @Test
    func deselectingTheConsoleReturnsToTheLogButLeavesOtherTabsAlone() {
        let model = GitToolWindowModel()
        model.setConsoleSelected(true)

        model.setConsoleSelected(false)
        #expect(model.pane == .log)

        model.showShelf()
        model.setConsoleSelected(false)
        #expect(model.pane == .shelf)

        model.showLog()
        model.setConsoleSelected(false)
        #expect(model.pane == .log)
    }

    @Test
    func consoleSelectionBindingReadsAndWritesThePane() {
        let model = GitToolWindowModel()
        let selection = model.consoleSelection
        #expect(selection.wrappedValue == false)

        selection.wrappedValue = true
        #expect(model.pane == .console)
        #expect(selection.wrappedValue)

        selection.wrappedValue = false
        #expect(model.pane == .log)
    }

    @Test
    func dragMovesTheWidthByTheTranslationAndClampsToTheRange() {
        var drag = GitPaneDividerDrag(range: 100...300)
        #expect(drag.startWidth == nil)

        #expect(drag.resolvedWidth(200, translation: 10) == 210)
        #expect(drag.startWidth == 200)
        #expect(drag.resolvedWidth(210, translation: 40) == 240)
        #expect(drag.resolvedWidth(240, translation: 600) == 300)
        #expect(drag.resolvedWidth(300, translation: -600) == 100)

        drag.end()
        #expect(drag.startWidth == nil)
        #expect(drag.resolvedWidth(300, translation: -50) == 250)
    }

    @Test
    func invertedDragMovesTheWidthTheOtherWayAndClamps() {
        var drag = GitPaneDividerDrag(range: 100...300, inverted: true)

        #expect(drag.resolvedWidth(200, translation: 40) == 160)
        #expect(drag.resolvedWidth(160, translation: 70) == 130)
        #expect(drag.resolvedWidth(130, translation: 600) == 100)
        #expect(drag.resolvedWidth(100, translation: -600) == 300)
    }
}
