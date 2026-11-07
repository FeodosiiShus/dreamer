//
//  FindNavigatorView.swift
//  Dreamder
//
//  Created by Ziyuan Zhao on 2022/3/20.
//

import SwiftUI

struct FindNavigatorView: View {
    @Environment(WorkspaceDocument.self) private var workspace

    private var state: WorkspaceDocument.SearchState {
        workspace.searchState ?? .init(workspace)
    }

    @State private var foundFilesCount: Int = 0
    @State private var searchResultCount: Int = 0
    @State private var findNavigatorStatus: WorkspaceDocument.SearchState.FindNavigatorStatus = .none
    @State private var findResultMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                FindNavigatorForm(state: state)
                FindNavigatorIndexBar(state: state)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)

            Rectangle()
                .fill(Islands.separator)
                .frame(height: 1)

            if findNavigatorStatus == .found {
                HStack(alignment: .center) {
                    Text("\(self.searchResultCount) results in \(self.foundFilesCount) files")
                        .font(Islands.smallFont)
                        .foregroundStyle(Islands.secondaryForeground)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(height: 24)

                Rectangle()
                    .fill(Islands.separator)
                    .frame(height: 1)
            }

            switch self.findNavigatorStatus {
            case .none:
                Spacer(minLength: 0)
            case .searching:
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)

                    Text("Searching")
                        .foregroundStyle(Islands.secondaryForeground)
                        .font(Islands.uiFont)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .replacing:
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)

                    Text("Replacing")
                        .foregroundStyle(Islands.secondaryForeground)
                        .font(Islands.uiFont)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .found:
                if self.searchResultCount == 0 {
                    CEContentUnavailableView(
                        "No Results",
                        description: "No Results for \"\(state.searchQuery)\" in \(state.scopeDescription)",
                        systemImage: "exclamationmark.magnifyingglass"
                    )
                } else {
                    FindNavigatorResultList()
                }
            case .replaced(let updatedFiles):
                CEContentUnavailableView(
                    "Replaced",
                    description: "Successfully replaced terms across \(updatedFiles) files",
                    systemImage: "checkmark.circle.fill"
                )
            case .failed(let errorMessage):
                CEContentUnavailableView(
                    "An Error Occurred",
                    description: "\(errorMessage)",
                    systemImage: "xmark.octagon.fill"
                )
            }
        }
        .background(Color.clear)
        .environment(\.colorScheme, .dark)
        .onChange(of: state.searchResult.count, initial: true) { _, count in
            self.foundFilesCount = count
        }
        .onChange(of: state.searchResultsCount, initial: true) { _, count in
            self.searchResultCount = count
        }
        .onChange(of: state.findNavigatorStatus, initial: true) { _, status in
            self.findNavigatorStatus = status
        }
    }
}
