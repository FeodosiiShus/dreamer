//
//  SourceControlCommands.swift
//  Dreamder
//
//  Created by Austin Condiff on 6/29/24.
//

import SwiftUI

struct SourceControlCommands: Commands {
    @State private var windowController: DreamderWindowController?

    @MergeConflictsMenuState private var hasUnmergedFiles

    var body: some Commands {
        CommandMenu("Git") {
            SourceControlMenu(windowController: windowController, hasUnmergedFiles: hasUnmergedFiles)
                .observeWindowController($windowController)
        }
    }
}

struct SourceControlMenu: View {
    let windowController: DreamderWindowController?
    let hasUnmergedFiles: Bool
    let sendAction: @MainActor (Selector) -> Void
    let presentConflicts: @MainActor (WorkspaceDocument) -> Void
    let runModal: @MainActor (NSAlert) -> NSApplication.ModalResponse

    init(
        windowController: DreamderWindowController?,
        hasUnmergedFiles: Bool,
        sendAction: @escaping @MainActor (Selector) -> Void = MenuResponderChain.send,
        presentConflicts: @escaping @MainActor (WorkspaceDocument) -> Void = MergeToolPresenter.showConflicts,
        runModal: @escaping @MainActor (NSAlert) -> NSApplication.ModalResponse = BranchesPopupPrompt.systemRunner
    ) {
        self.windowController = windowController
        self.hasUnmergedFiles = hasUnmergedFiles
        self.sendAction = sendAction
        self.presentConflicts = presentConflicts
        self.runModal = runModal
    }

    var sourceControlManager: SourceControlManager? {
        windowController?.workspace?.sourceControlManager
    }

    var body: some View {
        Button("Branches…", action: showBranches)
            .keymapShortcut(.gitBranches)

        Button("Resolve Conflicts…", action: resolveConflicts)
            .keymapShortcut(.gitResolveConflicts)
            .disabled(!hasUnmergedFiles)

        Group {
            Button("Commit…", action: showCommit)
                .keymapShortcut(.gitCommit)

            Button("Push…", action: showPush)
                .keymapShortcut(.gitPush)

            Button("Update Project…", action: updateProject)
                .keymapShortcut(.gitUpdateProject)

            Button("Fetch", action: fetch)
                .keymapShortcut(.gitFetch)

            Button("New Branch…", action: newBranch)
                .keymapShortcut(.gitNewBranch)

            Divider()

            Button("Pull…", action: showPull)
                .keymapShortcut(.gitPull)

            Button("Fetch Changes…", action: showFetchChanges)
                .keymapShortcut(.gitFetchChanges)

            Divider()

            Button("Stage All Changes", action: stageAll)
                .keymapShortcut(.gitStageAll)

            Button("Unstage All Changes", action: unstageAll)
                .keymapShortcut(.gitUnstageAll)

            Divider()

            Button("Stash Changes…", action: stash)
                .keymapShortcut(.gitStash)

            Divider()

            Button("Discard All Changes…", action: discardAll)
                .keymapShortcut(.gitDiscardAll)

            Divider()

            Button("Add Existing Remote…", action: addExistingRemote)
                .keymapShortcut(.gitAddRemote)
        }
        .disabled(windowController?.workspace == nil)
    }

    func showBranches() {
        sendAction(#selector(DreamderWindowController.showGitBranches(_:)))
    }

    func resolveConflicts() {
        guard let workspace = windowController?.workspace else { return }
        presentConflicts(workspace)
    }

    func showCommit() {
        windowController?.workspace?.toolWindowManager.show(.commit)
    }

    func showPush() {
        sourceControlManager?.pushSheetIsPresented = true
    }

    func updateProject() {
        guard let sourceControlManager else { return }
        Task {
            do {
                try await sourceControlManager.branchOpsUpdateProject()
            } catch {
                await sourceControlManager.showAlertForError(
                    title: "Failed to update project",
                    error: error
                )
            }
        }
    }

    func fetch() {
        guard let sourceControlManager else { return }
        Task {
            do {
                try await sourceControlManager.branchOpsFetchAll()
                await sourceControlManager.branchOpsRefresh()
            } catch {
                await sourceControlManager.showAlertForError(title: "Failed to fetch", error: error)
            }
        }
    }

    func newBranch() {
        guard let sourceControlManager else { return }
        guard let name = BranchesPopupPrompt.name(
            title: "New Branch",
            message: "Create a new branch from the current branch",
            placeholder: "Branch name",
            runModal: runModal
        ) else {
            return
        }
        Task {
            do {
                try await sourceControlManager.branchOpsCreateBranch(name: name, from: nil)
            } catch {
                await sourceControlManager.showAlertForError(
                    title: "Failed to create branch",
                    error: error
                )
            }
        }
    }

    func showPull() {
        sourceControlManager?.pullSheetIsPresented = true
    }

    func showFetchChanges() {
        sourceControlManager?.fetchSheetIsPresented = true
    }

    func stageAll() {
        guard let sourceControlManager else { return }
        if sourceControlManager.changedFiles.isEmpty {
            sourceControlManager.noChangesToStageAlertIsPresented = true
        } else {
            Task {
                do {
                    try await sourceControlManager.add(sourceControlManager.changedFiles.map { $0.fileURL })
                } catch {
                    await sourceControlManager.showAlertForError(
                        title: "Failed To Stage Changes",
                        error: error
                    )
                }
            }
        }
    }

    func unstageAll() {
        guard let sourceControlManager else { return }
        if sourceControlManager.changedFiles.isEmpty {
            sourceControlManager.noChangesToUnstageAlertIsPresented = true
        } else {
            Task {
                do {
                    try await sourceControlManager.reset(
                        sourceControlManager.changedFiles.map { $0.fileURL }
                    )
                } catch {
                    await sourceControlManager.showAlertForError(
                        title: "Failed To Unstage Changes",
                        error: error
                    )
                }
            }
        }
    }

    func stash() {
        if sourceControlManager?.changedFiles.isEmpty ?? false {
            sourceControlManager?.noChangesToStashAlertIsPresented = true
        } else {
            sourceControlManager?.stashSheetIsPresented = true
        }
    }

    func discardAll() {
        if sourceControlManager?.changedFiles.isEmpty ?? false {
            sourceControlManager?.noChangesToDiscardAlertIsPresented = true
        } else {
            sourceControlManager?.discardAllAlertIsPresented = true
        }
    }

    func addExistingRemote() {
        sourceControlManager?.addExistingRemoteSheetIsPresented = true
    }
}
