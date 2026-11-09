//
//  SourceControlNewBranchView.swift
//  Dreamder
//
//  Created by Albert Vinizhanau on 10/21/23.
//

import SwiftUI

@Observable
@MainActor
final class SourceControlNewBranchModel {
    var name: String = ""
    @ObservationIgnored let fromBranch: Binding<GitBranch?>
    @ObservationIgnored var manager: SourceControlManager?
    @ObservationIgnored var dismiss: (() -> Void)?
    @ObservationIgnored private(set) var submission: Task<Void, Never>?

    init(fromBranch: Binding<GitBranch?>) {
        self.fromBranch = fromBranch
    }

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
        guard let manager, let branch = fromBranch.wrappedValue ?? manager.currentBranch else { return }
        do {
            try await manager.newBranch(name: name, from: branch)
            dismiss?()
        } catch {
            await manager.showAlertForError(
                title: "Failed to create branch",
                error: error
            )
        }
    }
}

struct SourceControlNewBranchView: View {
    @Environment(\.dismiss)
    var dismiss

    @Environment(SourceControlManager.self) private var sourceControlManager

    @State private var model: SourceControlNewBranchModel
    @Binding var fromBranch: GitBranch?

    init(fromBranch: Binding<GitBranch?>, model: SourceControlNewBranchModel? = nil) {
        _fromBranch = fromBranch
        _model = State(initialValue: model ?? SourceControlNewBranchModel(fromBranch: fromBranch))
    }

    var body: some View {
        @Bindable var model = model
        if let branch = fromBranch ?? sourceControlManager.currentBranch {
            VStack(spacing: 0) {
                Form {
                    Section {
                        LabeledContent(
                            "From",
                            value: branch.isRemote
                                ? branch.longName.replacingOccurrences(of: "refs/remotes/", with: "")
                                : branch.name
                        )
                        TextField("To", value: $model.name, formatter: RegexFormatter(pattern: "[^a-zA-Z0-9_-]"))
                    } header: {
                        Text("Create a new branch")
                        Text(
                            "Create a branch from the current branch and switch to it. " +
                            "All uncommited changes will be preserved on the new branch. "
                        )
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
                        Text("Create")
                            .frame(minWidth: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.name.isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .frame(width: 500)
            .onAppear {
                model.attach(manager: sourceControlManager, dismiss: dismiss.callAsFunction)
            }
        }
    }
}
