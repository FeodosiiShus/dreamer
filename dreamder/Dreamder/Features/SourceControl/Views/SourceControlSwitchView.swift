//
//  SourceControlFetchView.swift
//  Dreamder
//
//  Created by Austin Condiff on 7/9/24.
//

import SwiftUI

@Observable
@MainActor
final class SourceControlSwitchModel {
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

    func submit(_ branch: GitBranch) {
        submission = Task { await perform(branch) }
    }

    func perform(_ branch: GitBranch) async {
        guard let manager else { return }
        do {
            if !manager.changedFiles.isEmpty {
                manager.stashSheetIsPresented = true
            } else {
                try await manager.checkoutBranch(branch: branch)
                dismiss?()
            }
        } catch {
            await manager.showAlertForError(title: "Failed to checkout", error: error)
        }
    }
}

struct SourceControlSwitchView: View {
    @Environment(\.dismiss)
    private var dismiss

    @Environment(SourceControlManager.self) private var sourceControlManager

    @State private var model: SourceControlSwitchModel

    var branch: GitBranch

    init(branch: GitBranch, model: SourceControlSwitchModel = SourceControlSwitchModel()) {
        self.branch = branch
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Do you want to switch to “\(branch.name)”?")
                        .font(.headline)
                    Text(
                        "All files in the local repository will switch from the current branch " +
                        "(“\(sourceControlManager.currentBranch?.name ?? "")”) to “\(branch.name)”."
                    )
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 20)
            .padding(.bottom, 10)
            .padding(.horizontal, 20)
            HStack {
                Spacer()
                Button(action: model.cancel) {
                    Text("Cancel")
                        .frame(minWidth: 56)
                }
                Button { model.submit(branch) } label: {
                    Text("Switch")
                        .frame(minWidth: 56)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 420)
        .onAppear {
            model.attach(manager: sourceControlManager, dismiss: dismiss.callAsFunction)
        }
    }
}
