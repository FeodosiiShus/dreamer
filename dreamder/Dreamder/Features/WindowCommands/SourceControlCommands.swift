//
//  SourceControlCommands.swift
//  Dreamder
//
//  Created by Austin Condiff on 6/29/24.
//

import SwiftUI

struct SourceControlCommands: Commands {
    @State private var windowController: DreamderWindowController?

    @State private var confirmDiscardChanges: Bool = false

    @MergeConflictsMenuState private var hasUnmergedFiles

    var sourceControlManager: SourceControlManager? {
        windowController?.workspace?.sourceControlManager
    }

    var body: some Commands {
        CommandMenu("Git") {
            Button("Branches…") {
                NSApp.sendAction(#selector(DreamderWindowController.showGitBranches(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("`", modifiers: [.control, .shift])

            Button("Resolve Conflicts…") {
                MergeToolPresenter.showConflictsForActiveWorkspace()
            }
            .disabled(!hasUnmergedFiles)

            Group {
                Button("Commit…") {
                    windowController?.workspace?.toolWindowManager.show(.commit)
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("Push…") {
                    sourceControlManager?.pushSheetIsPresented = true
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button("Update Project…") {
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
                .keyboardShortcut("t", modifiers: [.command])

                Button("Fetch") {
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

                Button("New Branch…") {
                    guard let sourceControlManager else { return }
                    guard let name = BranchesPopupPrompt.name(
                        title: "New Branch",
                        message: "Create a new branch from the current branch",
                        placeholder: "Branch name"
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
                .keyboardShortcut("n", modifiers: [.command, .option])

                Divider()

                Button("Pull…") {
                    sourceControlManager?.pullSheetIsPresented = true
                }
                .keyboardShortcut("x", modifiers: [.command, .option])

                Button("Fetch Changes…") {
                    sourceControlManager?.fetchSheetIsPresented = true
                }

                Divider()

                Button("Stage All Changes") {
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

                Button("Unstage All Changes") {
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

                Divider()

                Button("Stash Changes…") {
                    if sourceControlManager?.changedFiles.isEmpty ?? false {
                        sourceControlManager?.noChangesToStashAlertIsPresented = true
                    } else {
                        sourceControlManager?.stashSheetIsPresented = true
                    }
                }

                Divider()

                Button("Discard All Changes…") {
                    if sourceControlManager?.changedFiles.isEmpty ?? false {
                        sourceControlManager?.noChangesToDiscardAlertIsPresented = true
                    } else {
                        sourceControlManager?.discardAllAlertIsPresented = true
                    }
                }

                Divider()

                Button("Add Existing Remote…") {
                    sourceControlManager?.addExistingRemoteSheetIsPresented = true
                }
            }
            .disabled(windowController?.workspace == nil)
            .observeWindowController($windowController)
        }
    }
}
