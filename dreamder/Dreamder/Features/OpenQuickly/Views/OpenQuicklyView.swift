//
//  OpenQuicklyView.swift
//  DreamderModules/QuickOpen
//
//  Created by Pavel Kasila on 20.03.22.
//

import SwiftUI

struct OpenQuicklyView: View {
    @Environment(WorkspaceDocument.self) private var workspace

    private let onClose: () -> Void
    private let openFile: (CEWorkspaceFile) -> Void

    @Bindable private var openQuicklyViewModel: OpenQuicklyViewModel

    @State private var selectedItem: CEWorkspaceFile?
    @State private var fetchDebounce: Task<Void, Never>?

    init(
        state: OpenQuicklyViewModel,
        onClose: @escaping () -> Void,
        openFile: @escaping (CEWorkspaceFile) -> Void
    ) {
        self.openQuicklyViewModel = state
        self.onClose = onClose
        self.openFile = openFile
    }

    var body: some View {
        SearchPanelView(
            title: "Open Quickly",
            image: Image(systemName: "magnifyingglass"),
            options: $openQuicklyViewModel.searchResults,
            text: $openQuicklyViewModel.query,
            optionRowHeight: 40
        ) { searchResult in
            OpenQuicklyListItemView(
                baseDirectory: openQuicklyViewModel.fileURL,
                searchResult: searchResult
            )
        } preview: { searchResult in
            OpenQuicklyPreviewView(item: CEWorkspaceFile(url: searchResult.fileURL))
        } onRowClick: { searchResult in
            guard let file = workspace.workspaceFileManager?.getFile(
                searchResult.fileURL.relativePath,
                createIfNotFound: true
            ) else {
                return
            }
            openFile(file)
            openQuicklyViewModel.query = ""
            onClose()
        } onClose: {
            onClose()
        }
        .onChange(of: openQuicklyViewModel.query, initial: true) {
            fetchDebounce?.cancel()
            fetchDebounce = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                openQuicklyViewModel.fetchResults()
            }
        }
        .onDisappear {
            fetchDebounce?.cancel()
        }
    }
}
