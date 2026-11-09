//
//  SourceControlFetchView.swift
//  Dreamder
//
//  Created by Austin Condiff on 6/28/24.
//

import SwiftUI

@Observable
@MainActor
final class SourceControlFetchModel {
    @ObservationIgnored var manager: SourceControlManager?
    @ObservationIgnored var dismiss: (() -> Void)?

    func attach(manager: SourceControlManager, dismiss: @escaping () -> Void) {
        self.manager = manager
        self.dismiss = dismiss
    }

    func cancel() {
        dismiss?()
    }

    func perform() async {
        guard let manager else { return }
        do {
            try await manager.fetch()
            dismiss?()
        } catch {
            await manager.showAlertForError(title: "Failed to fetch changes", error: error)
        }
    }
}

struct SourceControlFetchView: View {
    @Environment(\.dismiss)
    private var dismiss

    @Environment(SourceControlManager.self) private var sourceControlManager
    @Environment(WorkspaceDocument.self) private var workspace

    @State private var model: SourceControlFetchModel

    init(model: SourceControlFetchModel = SourceControlFetchModel()) {
        _model = State(initialValue: model)
    }

    var projectName: String {
        Self.projectName(of: workspace)
    }

    static func projectName(of workspace: WorkspaceDocument) -> String {
        workspace.workspaceFileManager?.folderUrl.lastPathComponent ?? "Empty"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Fetching changes for “\(projectName)”...")
                        .font(.headline)
                    Text("Dreamder is fetching changes and updating the status of files in the local repository.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 10)
            .padding(.horizontal, 20)
            HStack {
                HStack(spacing: 7.5) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                    Text("Fetching changes...")
                        .font(.subheadline)
                }
                Spacer()
                Button(action: model.cancel) {
                    Text("Cancel")
                        .frame(minWidth: 48)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 420)
        .task {
            model.attach(manager: sourceControlManager, dismiss: dismiss.callAsFunction)
            await model.perform()
        }
    }
}
