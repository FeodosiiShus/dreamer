//
//  SourceControlNavigatorView.swift
//  Dreamder
//
//  Created by Nanashi Li on 2022/05/20.
//

import SwiftUI

struct SourceControlNavigatorView: View {
    @Environment(WorkspaceDocument.self) private var workspace

    @AppSettings(\.sourceControl.general.fetchRefreshServerStatus)
    var fetchRefreshServerStatus

    var body: some View {
        if let sourceControlManager = workspace.sourceControlManager {
            VStack(spacing: 0) {
                SourceControlNavigatorTabs()
                    .environment(sourceControlManager)
                    .task {
                        do {
                            while true {
                                if fetchRefreshServerStatus {
                                    try await sourceControlManager.fetch()
                                }
                                try await Task.sleep(for: .seconds(10))
                            }
                        } catch {
                            // TODO: if source fetching fails, display message
                        }
                    }
            }
        }
    }
}

struct SourceControlNavigatorTabs: View {
    @Environment(SourceControlManager.self) private var sourceControlManager
    @State private var selectedSection: Int = 0

    var body: some View {
        if sourceControlManager.isGitRepository {
            SegmentedControl(
                $selectedSection,
                options: ["Changes", "History", "Repository"],
                prominent: true
            )
            .frame(maxWidth: .infinity)
            .frame(height: 27)
            .padding(.horizontal, 8)
            Divider()
            if selectedSection == 0 {
                SourceControlNavigatorChangesView()
            }
            if selectedSection == 1 {
                SourceControlNavigatorHistoryView()
            }
            if selectedSection == 2 {
                SourceControlNavigatorRepositoryView()
            }
        } else {
            CEContentUnavailableView(
                "No Repository",
                 description: "This project is not a git repository.",
                 systemImage: "externaldrive.fill",
                 actions: {
                    Button("Initialize") {
                        Task {
                            do {
                                try await sourceControlManager.initiate()
                            } catch {
                                await sourceControlManager.showAlertForError(
                                    title: "Failed to initialize repository",
                                    error: error
                                )
                            }
                        }
                    }
                }
            )
        }
    }
}
