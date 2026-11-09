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

    private var showsResults: Bool {
        (findNavigatorStatus == .found || findNavigatorStatus == .searching) && searchResultCount > 0
    }

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

            if showsResults || findNavigatorStatus == .found {
                HStack(alignment: .center, spacing: 6) {
                    Text("\(self.searchResultCount) results in \(self.foundFilesCount) files")
                        .font(Islands.smallFont)
                        .foregroundStyle(Islands.secondaryForeground)
                    if findNavigatorStatus == .searching {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(height: 24)

                Rectangle()
                    .fill(Islands.separator)
                    .frame(height: 1)
            }

            if let notice = state.replaceNotice {
                Text(notice)
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.errorForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }

            if showsResults && state.selectedMode.isReplaceMode {
                FindNavigatorReplaceBar(state: state)
            }

            if showsResults {
                FindNavigatorResultList()
            } else {
                placeholder
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

    @ViewBuilder private var placeholder: some View {
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
            CEContentUnavailableView(
                "No Results",
                description: "No Results for \"\(state.searchQuery)\" in \(state.scopeDescription)",
                systemImage: "exclamationmark.magnifyingglass"
            )
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
}

struct FindNavigatorReplaceBar: View {
    @Bindable var state: WorkspaceDocument.SearchState

    private var hasSelection: Bool {
        state.resultSelection != nil
    }

    private var canReplace: Bool {
        hasSelection && state.replacementError == nil
    }

    var body: some View {
        HStack(spacing: 6) {
            FindNavigatorBarButton(title: "Replace", isEnabled: canReplace, action: replaceSelected)
            FindNavigatorBarButton(title: "Skip", isEnabled: hasSelection, action: skipSelected)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    func replaceSelected() {
        Task { await state.replaceSelected() }
    }

    func skipSelected() {
        state.toggleSkipSelected()
    }
}

struct FindNavigatorBarButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Islands.smallFont)
                .foregroundStyle(isEnabled ? Islands.foreground : Islands.disabledForeground)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: Islands.controlRadius)
                        .fill(Islands.actionHover)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
