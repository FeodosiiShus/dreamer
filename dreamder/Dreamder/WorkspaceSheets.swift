//
//  WorkspaceSheets.swift
//  Dreamder
//
//  Created by Austin Condiff on 7/1/24.
//

import SwiftUI

@MainActor
@Observable
final class WorkspaceSheetPresentation {
    private let manager: SourceControlManager

    init(manager: SourceControlManager) {
        self.manager = manager
    }

    var isPushPresented: Bool {
        get { manager.pushSheetIsPresented && !manager.addExistingRemoteSheetIsPresented }
        set { manager.pushSheetIsPresented = newValue }
    }

    var isPullPresented: Bool {
        get {
            manager.pullSheetIsPresented
                && !manager.addExistingRemoteSheetIsPresented
                && !manager.stashSheetIsPresented
        }
        set { manager.pullSheetIsPresented = newValue }
    }

    var switchBranch: GitBranch? {
        get { manager.switchToBranch != nil && manager.stashSheetIsPresented ? nil : manager.switchToBranch }
        set { manager.switchToBranch = newValue }
    }

    func dismissDiscardAllAlert() {
        manager.discardAllAlertIsPresented = false
    }
}

struct NoUncommittedChangesAlert: ViewModifier {
    let title: LocalizedStringKey
    @Binding var isPresented: Bool

    func dismiss() {
        isPresented = false
    }

    func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            Button("OK", role: .cancel, action: dismiss)
        } message: {
            Text("There are no uncommitted changes in the local repository for this project.")
        }
    }
}

private extension View {
    func noUncommittedChangesAlert(_ title: LocalizedStringKey, isPresented: Binding<Bool>) -> some View {
        modifier(NoUncommittedChangesAlert(title: title, isPresented: isPresented))
    }
}

struct WorkspaceSheets: View {
    @Environment(SourceControlManager.self) private var sourceControlManager

    var body: some View {
        @Bindable var sourceControlManager = sourceControlManager
        @Bindable var presentation = WorkspaceSheetPresentation(manager: sourceControlManager)
        EmptyView()
            .sheet(isPresented: $presentation.isPushPresented) { SourceControlPushView() }
            .sheet(isPresented: $presentation.isPullPresented) { SourceControlPullView() }
            .sheet(isPresented: $sourceControlManager.fetchSheetIsPresented) { SourceControlFetchView() }
            .sheet(isPresented: $sourceControlManager.stashSheetIsPresented) { SourceControlStashView() }
            .sheet(isPresented: $sourceControlManager.addExistingRemoteSheetIsPresented) {
                SourceControlAddExistingRemoteView()
            }
            .sheet(item: $presentation.switchBranch) { branch in SourceControlSwitchView(branch: branch) }
            .alert(
                "Do you want to discard all uncommitted, local changes?",
                isPresented: $sourceControlManager.discardAllAlertIsPresented
            ) {
                Button("Discard", role: .destructive, action: sourceControlManager.discardAllChanges)
                Button("Cancel", role: .cancel, action: presentation.dismissDiscardAllAlert)
            } message: {
                Text("This action cannot be undone.")
            }
            .noUncommittedChangesAlert(
                "Cannot Stage Changes",
                isPresented: $sourceControlManager.noChangesToStageAlertIsPresented
            )
            .noUncommittedChangesAlert(
                "Cannot Unstage Changes",
                isPresented: $sourceControlManager.noChangesToUnstageAlertIsPresented
            )
            .noUncommittedChangesAlert(
                "Cannot Stash Changes",
                isPresented: $sourceControlManager.noChangesToStashAlertIsPresented
            )
            .noUncommittedChangesAlert(
                "Cannot Discard Changes",
                isPresented: $sourceControlManager.noChangesToDiscardAlertIsPresented
            )
    }
}
