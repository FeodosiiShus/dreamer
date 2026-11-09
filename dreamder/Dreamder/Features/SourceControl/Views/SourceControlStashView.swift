//
//  SourceControlAddRemoteView.swift
//  Dreamder
//
//  Created by Austin Condiff on 11/17/23.
//

import SwiftUI

@Observable
@MainActor
final class SourceControlStashModel {
    var message: String = ""
    var applyStashAfterOperation: Bool = false
    @ObservationIgnored var manager: SourceControlManager?
    @ObservationIgnored var dismiss: (() -> Void)?
    @ObservationIgnored private(set) var submission: Task<Void, Never>?

    func attach(manager: SourceControlManager, dismiss: @escaping () -> Void) {
        self.manager = manager
        self.dismiss = dismiss
    }

    func cancel() {
        message = ""
        dismiss?()
    }

    func submit() {
        submission = Task { await perform() }
    }

    func perform() async {
        guard let manager else { return }
        do {
            try await manager.stashChanges(message: message.isEmpty ? nil : message)
            message = ""

            if manager.pullSheetIsPresented || manager.switchToBranch != nil {
                if manager.pullSheetIsPresented {
                    try await manager.pull(
                        remote: manager.operationRemote?.name,
                        branch: manager.operationBranch?.name,
                        rebase: manager.operationRebase
                    )
                }

                if let branch = manager.switchToBranch {
                    try await manager.checkoutBranch(branch: branch)
                }

                if applyStashAfterOperation {
                    guard let lastStashEntry = manager.stashEntries.first else {
                        throw NSError(
                            domain: "SourceControl",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Could not find last stash"]
                        )
                    }
                    try await manager.applyStashEntry(stashEntry: lastStashEntry)
                }

                manager.operationRemote = nil
                manager.operationBranch = nil
                manager.pullSheetIsPresented = false
                manager.switchToBranch = nil
            }

            dismiss?()
        } catch {
            await manager.showAlertForError(title: "Failed to stash changes", error: error)
        }
    }
}

struct SourceControlStashView: View {
    @Environment(SourceControlManager.self) private var sourceControlManager
    @Environment(\.dismiss)
    private var dismiss

    @State private var model: SourceControlStashModel

    init(model: SourceControlStashModel = SourceControlStashModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        @Bindable var form = model
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("", text: $form.message, prompt: Text("Message (optional)"), axis: .vertical)
                        .labelsHidden()
                        .lineLimit(3...3)
                        .contentShape(Rectangle())
                        .frame(height: 48)
                } header: {
                    Text("Stash Changes")
                    Group {
                        if sourceControlManager.pullSheetIsPresented
                            || sourceControlManager.switchToBranch != nil {
                            Text("Your local repository has uncommitted changes that need to be stashed " +
                                 "before you can continue. Enter a description for your changes.")
                        } else {
                            Text("Enter a description for your stashed changes so you can reference them later. " +
                                 "Stashes will appear in the Source Control navigator for your repository.")
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                }
                if sourceControlManager.pullSheetIsPresented
                    || sourceControlManager.switchToBranch != nil {
                    Section {
                        Toggle("Apply stash after operation", isOn: $form.applyStashAfterOperation)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .onSubmit(model.submit)
            HStack {
                Spacer()
                Button(action: model.cancel) {
                    Text("Cancel")
                        .frame(minWidth: 56)
                }
                Button(action: model.submit) {
                    Text(
                        sourceControlManager.pullSheetIsPresented
                        ? "Stash and Pull"
                        : sourceControlManager.switchToBranch != nil
                        ? "Stash and Switch"
                        : "Stash"
                    )
                    .frame(minWidth: 56)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 500)
        .onAppear {
            model.attach(manager: sourceControlManager, dismiss: dismiss.callAsFunction)
        }
    }
}
