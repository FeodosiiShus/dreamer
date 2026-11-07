//
//  SourceControlPushView.swift
//  Dreamder
//
//  Created by Austin Condiff on 6/26/24.
//

import SwiftUI

struct SourceControlPushView: View {
    @Environment(\.dismiss)
    private var dismiss

    @Environment(SourceControlManager.self) private var sourceControlManager

    @State var loading: Bool = false

    var body: some View {
        @Bindable var manager = sourceControlManager
        VStack(spacing: 0) {
            Form {
                Section {
                    RemoteBranchPicker(
                        branch: $manager.operationBranch,
                        remote: $manager.operationRemote,
                        onSubmit: submit,
                        canCreateBranch: true
                    )
                } header: {
                    Text("Push local changes to")
                }
                Section {
                    Toggle("Force", isOn: $manager.operationForce)
                    Toggle("Include Tags", isOn: $manager.operationIncludeTags)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            HStack {
                if loading {
                    HStack(spacing: 7.5) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                        Text("Pushing changes...")
                            .font(.subheadline)
                    }
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .frame(minWidth: 56)
                }
                .disabled(loading)
                Button(action: submit) {
                    Text("Push")
                        .frame(minWidth: 56)
                }
                .buttonStyle(.borderedProminent)
                .disabled(loading)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(minWidth: 500)
    }

    /// Pushes commited changes to specified remote and branch
    func submit() {
        Task {
            do {
                self.loading = true
                try await sourceControlManager.push(
                    remote: sourceControlManager.operationRemote?.name ?? nil,
                    branch: sourceControlManager.operationBranch?.name ?? nil,
                    setUpstream: sourceControlManager.currentBranch?.upstream == nil,
                    force: sourceControlManager.operationForce,
                    tags: sourceControlManager.operationIncludeTags
                )
                self.loading = false
                dismiss()
            } catch {
                self.loading = false
                await sourceControlManager.showAlertForError(title: "Failed to push", error: error)
            }
        }
    }
}
