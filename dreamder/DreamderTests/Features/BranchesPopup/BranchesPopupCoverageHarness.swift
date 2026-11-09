import AppKit
import Foundation
import Testing
@testable import Dreamder

final class BranchesPopupCoverageCounter {
    var value = 0
}

@MainActor
final class BranchesPopupCoverageHarness {
    let fixture: GitMergeFixture
    let manager: SourceControlManager
    let workspace: WorkspaceDocument
    let model: BranchesPopupViewModel
    private let dismissalCounter: BranchesPopupCoverageCounter
    var branchDialogTitles: [String] = []
    var confirmTitles: [String] = []
    var worktreeSuggestions: [String] = []
    var errors: [String] = []
    var notifications: [String] = []
    var compares: [(branch: String, current: String)] = []
    var presentedRows: [BranchesPopupRow] = []

    var dismissals: Int {
        dismissalCounter.value
    }

    private init(fixture: GitMergeFixture, defaults: UserDefaults) {
        self.fixture = fixture
        let counter = BranchesPopupCoverageCounter()
        let manager = SourceControlManager(workspaceURL: fixture.root, editorManager: EditorManager())
        let workspace = WorkspaceDocument()
        workspace.sourceControlManager = manager
        self.dismissalCounter = counter
        self.manager = manager
        self.workspace = workspace
        self.model = BranchesPopupViewModel(
            sourceControlManager: manager,
            workspace: workspace,
            defaults: defaults,
            dismiss: { counter.value += 1 }
        )
        configure()
    }

    private func configure() {
        model.dialogs = BranchesPopupDialogs(
            branchDialog: { [weak self] request in
                self?.branchDialogTitles.append(request.title)
                return nil
            },
            confirm: { [weak self] title, _, _ in
                self?.confirmTitles.append(title)
                return false
            },
            unmergedDelete: { _, _ in .cancel },
            checkoutRemoteName: { _, _ in nil },
            checkoutRemoteLocalCommits: { _, _, _ in .cancel },
            worktreePath: { [weak self] suggested in
                self?.worktreeSuggestions.append(suggested)
                return nil
            },
            error: { [weak self] title, _ in
                self?.errors.append(title)
            }
        )
        model.namePrompt = { _, _, _, _ in nil }
        model.notify = { [weak self] request in
            self?.notifications.append(request.title)
        }
        model.presentRefActions = { [weak self] row in
            self?.presentedRows.append(row)
        }
        model.comparePresenter = { [weak self] _, branch, current in
            self?.compares.append((branch, current))
        }
        model.openConflicts = {}
    }

    static func local(in directory: URL, defaults: UserDefaults) async throws -> BranchesPopupCoverageHarness {
        try await BranchesPopupTemplateRepository.local.copy(into: directory)
        let harness = BranchesPopupCoverageHarness(fixture: GitMergeFixture(existing: directory), defaults: defaults)
        try await harness.load()
        return harness
    }

    static func cloned(in directory: URL, defaults: UserDefaults) async throws -> BranchesPopupCoverageHarness {
        try await BranchesPopupTemplateRepository.cloned.copy(into: directory)
        let clone = GitMergeFixture(existing: directory.appending(path: "clone"))
        try await clone.run(
            "remote",
            "set-url",
            "origin",
            directory.appending(path: "origin").path(percentEncoded: false)
        )
        let harness = BranchesPopupCoverageHarness(fixture: clone, defaults: defaults)
        try await harness.load()
        return harness
    }

    func load() async throws {
        await manager.branchOpsRefresh()
        await model.reload()
        try await eventually { !model.isLoading && model.rows.contains { $0.ref != nil } }
    }

    func ref(_ kind: BranchesPopupRef.Kind, _ shortName: String) throws -> BranchesPopupRef {
        let candidates = kind == .remote ? model.remoteBranchRefs : model.sections.flatMap(\.refs)
        return try #require(candidates.first { $0.kind == kind && $0.shortName == shortName })
    }

    func row(_ kind: BranchesPopupRowKind, shortName: String? = nil) throws -> BranchesPopupRow {
        try #require(model.rows.first { row in
            row.kind == kind && (shortName == nil || row.ref?.shortName == shortName)
        })
    }

    func waitIdle() async throws {
        try await eventually { model.runningOperations == 0 }
    }

    func perform(_ title: String, in menu: NSMenu) async throws {
        let index = menu.indexOfItem(withTitle: title)
        try #require(index >= 0)
        menu.performActionForItem(at: index)
        try await waitIdle()
    }
}

@MainActor
enum BranchesPopupCoverageKeys {
    static func event(
        _ keyCode: UInt16,
        flags: NSEvent.ModifierFlags = [],
        in window: NSWindow
    ) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    static func optionalEvent(_ keyCode: UInt16, in window: NSWindow) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )
    }

    static func titles(of menu: NSMenu) -> [String] {
        menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
    }
}
