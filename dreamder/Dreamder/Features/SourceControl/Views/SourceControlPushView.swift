//
//  SourceControlPushView.swift
//  Dreamder
//
//  Created by Austin Condiff on 6/26/24.
//

import SwiftUI

@Observable
@MainActor
final class SourceControlPushModel {
    var loading: Bool = false
    @ObservationIgnored var manager: SourceControlManager?
    @ObservationIgnored var dismiss: (() -> Void)?
    @ObservationIgnored private(set) var submission: Task<Void, Never>?

    func attach(manager: SourceControlManager, dismiss: @escaping () -> Void) {
        self.manager = manager
        self.dismiss = dismiss
    }

    func cancel() {
        dismiss?()
    }

    func submit() {
        submission = Task { await perform() }
    }

    func perform() async {
        guard let manager else { return }
        loading = true
        do {
            try await manager.push(
                remote: manager.operationRemote?.name,
                branch: manager.operationBranch?.name,
                setUpstream: manager.currentBranch?.upstream == nil,
                force: manager.operationForce,
                tags: manager.operationIncludeTags
            )
            loading = false
            dismiss?()
        } catch {
            loading = false
            await manager.showAlertForError(title: "Failed to push", error: error)
        }
    }
}

struct SourceControlPushView: View {
    @Environment(\.dismiss)
    private var dismiss

    @Environment(SourceControlManager.self) private var sourceControlManager

    @State private var model: SourceControlPushModel

    init(model: SourceControlPushModel = SourceControlPushModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        @Bindable var manager = sourceControlManager
        VStack(spacing: 0) {
            Form {
                Section {
                    RemoteBranchPicker(
                        branch: $manager.operationBranch,
                        remote: $manager.operationRemote,
                        onSubmit: model.submit,
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
                if model.loading {
                    HStack(spacing: 7.5) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                        Text("Pushing changes...")
                            .font(.subheadline)
                    }
                }
                Spacer()
                Button(action: model.cancel) {
                    Text("Cancel")
                        .frame(minWidth: 56)
                }
                .disabled(model.loading)
                Button(action: model.submit) {
                    Text("Push")
                        .frame(minWidth: 56)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.loading)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(minWidth: 500)
        .onAppear {
            model.attach(manager: sourceControlManager, dismiss: dismiss.callAsFunction)
        }
    }
}
