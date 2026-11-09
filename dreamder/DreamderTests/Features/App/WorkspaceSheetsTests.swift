import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct WorkspaceSheetsTests {
    enum SheetKind: String, CaseIterable, CustomTestStringConvertible {
        case push
        case pull
        case fetch
        case stash
        case addRemote
        case switchBranch

        var testDescription: String { rawValue }

        @MainActor
        func present(on manager: SourceControlManager) {
            switch self {
            case .push: manager.pushSheetIsPresented = true
            case .pull: manager.pullSheetIsPresented = true
            case .fetch: manager.fetchSheetIsPresented = true
            case .stash: manager.stashSheetIsPresented = true
            case .addRemote: manager.addExistingRemoteSheetIsPresented = true
            case .switchBranch:
                manager.switchToBranch = GitBranch(
                    name: "feature",
                    longName: "refs/heads/feature",
                    upstream: nil,
                    ahead: 0,
                    behind: 0
                )
            }
        }

        @MainActor
        func dismiss(on manager: SourceControlManager) {
            switch self {
            case .push: manager.pushSheetIsPresented = false
            case .pull: manager.pullSheetIsPresented = false
            case .fetch: manager.fetchSheetIsPresented = false
            case .stash: manager.stashSheetIsPresented = false
            case .addRemote: manager.addExistingRemoteSheetIsPresented = false
            case .switchBranch: manager.switchToBranch = nil
            }
        }
    }

    enum AlertKind: String, CaseIterable, CustomTestStringConvertible {
        case discardAll
        case noChangesToStage
        case noChangesToUnstage
        case noChangesToStash
        case noChangesToDiscard

        var testDescription: String { rawValue }

        var title: String {
            switch self {
            case .discardAll: "Do you want to discard all uncommitted, local changes?"
            case .noChangesToStage: "Cannot Stage Changes"
            case .noChangesToUnstage: "Cannot Unstage Changes"
            case .noChangesToStash: "Cannot Stash Changes"
            case .noChangesToDiscard: "Cannot Discard Changes"
            }
        }

        @MainActor
        func present(on manager: SourceControlManager) {
            switch self {
            case .discardAll: manager.discardAllAlertIsPresented = true
            case .noChangesToStage: manager.noChangesToStageAlertIsPresented = true
            case .noChangesToUnstage: manager.noChangesToUnstageAlertIsPresented = true
            case .noChangesToStash: manager.noChangesToStashAlertIsPresented = true
            case .noChangesToDiscard: manager.noChangesToDiscardAlertIsPresented = true
            }
        }
    }

    @MainActor
    private struct Rig {
        let workspace: WorkspaceDocument
        let manager: SourceControlManager
        let hosted: HostedView

        init(in directory: URL) throws {
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            let manager = try #require(workspace.sourceControlManager)
            self.workspace = workspace
            self.manager = manager
            self.hosted = try HostedViewFixture.hostInWorkspace(workspace) {
                WorkspaceSheets().environment(manager)
            }
        }

        func endSheets() {
            while let sheet = hosted.window.attachedSheet {
                hosted.window.endSheet(sheet)
            }
        }

        func close() {
            endSheets()
            hosted.close()
            workspace.close()
        }
    }

    private func makeManager(in directory: URL) -> SourceControlManager {
        SourceControlManager(workspaceURL: directory, editorManager: EditorManager())
    }

    private func branch(_ name: String) -> GitBranch {
        GitBranch(name: name, longName: "refs/heads/\(name)", upstream: nil, ahead: 0, behind: 0)
    }

    @Test(arguments: SheetKind.allCases)
    func everySheetIsPresentedWhileItsFlagIsSetAndDismissedWhenItIsCleared(kind: SheetKind) async throws {
        try await withTempDir { directory in
            let rig = try Rig(in: directory)
            defer { rig.close() }
            try await rig.hosted.settle()
            #expect(rig.hosted.window.attachedSheet == nil)

            kind.present(on: rig.manager)
            try await eventually(timeout: .seconds(30)) { rig.hosted.window.attachedSheet != nil }

            kind.dismiss(on: rig.manager)
            try await eventually(timeout: .seconds(30)) { rig.hosted.window.attachedSheet == nil }
        }
    }

    @Test(arguments: AlertKind.allCases)
    func everyAlertFlagPresentsItsAlert(kind: AlertKind) async throws {
        try await withTempDir { directory in
            let rig = try Rig(in: directory)
            defer { rig.close() }
            try await rig.hosted.settle()

            kind.present(on: rig.manager)

            try await eventually(timeout: .seconds(30)) {
                DreamderHeadless.suppressedModals.contains(kind.title) || rig.hosted.window.attachedSheet != nil
            }
        }
    }

    @Test
    func pushSheetYieldsToTheAddRemoteSheet() throws {
        try withTempDir { directory in
            let manager = makeManager(in: directory)
            let presentation = WorkspaceSheetPresentation(manager: manager)
            #expect(presentation.isPushPresented == false)

            presentation.isPushPresented = true
            #expect(manager.pushSheetIsPresented)
            #expect(presentation.isPushPresented)

            manager.addExistingRemoteSheetIsPresented = true
            #expect(manager.pushSheetIsPresented)
            #expect(presentation.isPushPresented == false)

            manager.addExistingRemoteSheetIsPresented = false
            presentation.isPushPresented = false
            #expect(manager.pushSheetIsPresented == false)
        }
    }

    @Test
    func pullSheetYieldsToTheAddRemoteAndStashSheets() throws {
        try withTempDir { directory in
            let manager = makeManager(in: directory)
            let presentation = WorkspaceSheetPresentation(manager: manager)

            presentation.isPullPresented = true
            #expect(manager.pullSheetIsPresented)
            #expect(presentation.isPullPresented)

            manager.addExistingRemoteSheetIsPresented = true
            #expect(presentation.isPullPresented == false)

            manager.addExistingRemoteSheetIsPresented = false
            manager.stashSheetIsPresented = true
            #expect(presentation.isPullPresented == false)

            manager.stashSheetIsPresented = false
            #expect(presentation.isPullPresented)

            presentation.isPullPresented = false
            #expect(manager.pullSheetIsPresented == false)
        }
    }

    @Test
    func switchSheetYieldsToTheStashSheet() throws {
        try withTempDir { directory in
            let manager = makeManager(in: directory)
            let presentation = WorkspaceSheetPresentation(manager: manager)
            #expect(presentation.switchBranch == nil)

            presentation.switchBranch = branch("feature")
            #expect(manager.switchToBranch?.name == "feature")
            #expect(presentation.switchBranch?.name == "feature")

            manager.stashSheetIsPresented = true
            #expect(manager.switchToBranch?.name == "feature")
            #expect(presentation.switchBranch == nil)

            manager.stashSheetIsPresented = false
            presentation.switchBranch = nil
            #expect(manager.switchToBranch == nil)
        }
    }

    @Test
    func cancellingTheDiscardAllAlertClearsItsFlag() throws {
        try withTempDir { directory in
            let manager = makeManager(in: directory)
            let presentation = WorkspaceSheetPresentation(manager: manager)
            manager.discardAllAlertIsPresented = true

            presentation.dismissDiscardAllAlert()

            #expect(manager.discardAllAlertIsPresented == false)
        }
    }

    @Test
    func acknowledgingTheNoChangesAlertClearsItsBinding() throws {
        try withTempDir { directory in
            let manager = makeManager(in: directory)
            manager.noChangesToStageAlertIsPresented = true
            let alert = NoUncommittedChangesAlert(
                title: "Cannot Stage Changes",
                isPresented: Binding(
                    get: { manager.noChangesToStageAlertIsPresented },
                    set: { manager.noChangesToStageAlertIsPresented = $0 }
                )
            )

            alert.dismiss()

            #expect(manager.noChangesToStageAlertIsPresented == false)
        }
    }
}
