//
//  SourceControlPullView.swift
//  Dreamder
//
//  Created by Austin Condiff on 6/28/24.
//

import SwiftUI

@Observable
@MainActor
final class SourceControlPullModel {
    var loading: Bool = false
    @ObservationIgnored let gitConfig: GitConfigClient
    @ObservationIgnored var manager: SourceControlManager?
    @ObservationIgnored var dismiss: (() -> Void)?
    @ObservationIgnored private(set) var submission: Task<Void, Never>?
    @ObservationIgnored private(set) var settingsLoad: Task<Void, Never>?

    init(gitConfig: GitConfigClient = GitConfigClient(shellClient: currentWorld.shellClient)) {
        self.gitConfig = gitConfig
    }

    func attach(manager: SourceControlManager, dismiss: @escaping () -> Void) {
        self.manager = manager
        self.dismiss = dismiss
        settingsLoad = Task { await loadPullSettings() }
    }

    func cancel() {
        dismiss?()
    }

    func submit() {
        submission = Task { await perform() }
    }

    func loadPullSettings() async {
        guard let manager else { return }
        do {
            let preferRebase: Bool = try await gitConfig.get(key: "pull.rebase", global: true) ?? false
            if preferRebase {
                manager.operationRebase = true
            }
        } catch {
            await manager.showAlertForError(
                title: "Failed to read pull settings",
                error: error
            )
        }
    }

    func perform() async {
        guard let manager else { return }
        do {
            if !manager.changedFiles.isEmpty {
                manager.stashSheetIsPresented = true
            } else {
                loading = true
                try await manager.pull(
                    remote: manager.operationRemote?.name,
                    branch: manager.operationBranch?.name,
                    rebase: manager.operationRebase
                )
                loading = false
                dismiss?()
            }
        } catch {
            loading = false
            await manager.showAlertForError(title: "Failed to pull", error: error)
        }
    }
}

struct SourceControlPullView: View {
    @Environment(\.dismiss)
    private var dismiss

    @Environment(SourceControlManager.self) private var sourceControlManager

    @State private var model: SourceControlPullModel

    init(model: SourceControlPullModel = SourceControlPullModel()) {
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
                        canCreateBranch: false
                    )
                } header: {
                    Text("Pull remote changes from")
                }
                Section {
                    Toggle("Rebase local changes onto upstream changes", isOn: $manager.operationRebase)
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
                        Text("Pulling changes...")
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
                    Text("Pull")
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
