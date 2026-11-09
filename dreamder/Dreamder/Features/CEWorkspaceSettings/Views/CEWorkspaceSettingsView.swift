//
//  CEWorkspaceSettingsView.swift
//  Dreamder
//
//  Created by Tommy Ludwig on 01.07.24.
//

import SwiftUI

@Observable
final class CEWorkspaceSettingsSheetState {
    var selectedTaskID: UUID?
    var showsAddTaskSheet: Bool

    init(selectedTaskID: UUID? = nil, showsAddTaskSheet: Bool = false) {
        self.selectedTaskID = selectedTaskID
        self.showsAddTaskSheet = showsAddTaskSheet
    }

    func beginAddingTask() {
        selectedTaskID = nil
        showsAddTaskSheet = true
    }
}

struct CEWorkspaceSettingsView: View {
    var dismiss: () -> Void

    @Environment(CEWorkspaceSettings.self) private var workspaceSettingsManager
    @Environment(WorkspaceDocument.self) private var workspace

    @State private var sheetState: CEWorkspaceSettingsSheetState

    init(dismiss: @escaping () -> Void, selectedTaskID: UUID? = nil, showAddTaskSheet: Bool = false) {
        self.dismiss = dismiss
        _sheetState = State(
            initialValue: CEWorkspaceSettingsSheetState(
                selectedTaskID: selectedTaskID,
                showsAddTaskSheet: showAddTaskSheet
            )
        )
    }

    var body: some View {
        @Bindable var workspaceSettingsManager = workspaceSettingsManager
        @Bindable var sheetState = sheetState
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField(
                        "Name",
                        text: $workspaceSettingsManager.settings.project.projectName
                    )
                    .accessibilityLabel("Workspace Name")
                } header: {
                    Text("Workspace")
                        .accessibilityHidden(true)
                }

                Section {
                    CEWorkspaceSettingsTaskListView(
                        settings: workspaceSettingsManager.settings,
                        selectedTaskID: $sheetState.selectedTaskID,
                        showAddTaskSheet: $sheetState.showsAddTaskSheet
                    )
                } header: {
                    Text("Tasks")
                } footer: {
                    HStack {
                        Spacer()
                        Button(action: sheetState.beginAddingTask) {
                            Text("Add Task...")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()
            HStack {
                Spacer()
                Button(action: dismiss) {
                    Text("Done")
                        .frame(minWidth: 56)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .sheet(isPresented: $sheetState.showsAddTaskSheet) {
            if let selectedTaskIndex = workspaceSettingsManager.settings.tasks.firstIndex(where: {
                $0.id == sheetState.selectedTaskID
            }) {
                EditCETaskView(
                    task: workspaceSettingsManager.settings.tasks[selectedTaskIndex],
                    selectedTaskIndex: selectedTaskIndex
                )
            } else {
                AddCETaskView()
            }
        }
    }
}
