//
//  SearchResultList.swift
//  Dreamder
//
//  Created by Ziyuan Zhao on 2022/3/22.
//

import SwiftUI

struct FindNavigatorResultList: NSViewControllerRepresentable {

    @Environment(WorkspaceDocument.self) private var workspace

    typealias NSViewControllerType = FindNavigatorListViewController

    func makeNSViewController(context: Context) -> FindNavigatorListViewController {
        let controller = FindNavigatorListViewController(workspace: workspace)
        controller.setSearchResults(workspace.searchState?.searchResult ?? [])
        controller.rowHeight = Double(Islands.listRowHeight)
        context.coordinator.controller = controller
        return controller
    }

    func updateNSViewController(_ nsViewController: FindNavigatorListViewController, context: Context) {
        nsViewController.updateNewSearchResults(
            workspace.searchState?.searchResult ?? []
        )
        return
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            state: workspace.searchState,
            controller: nil
        )
    }

    class Coordinator: NSObject {
        init(state: WorkspaceDocument.SearchState?, controller: FindNavigatorListViewController?) {
            self.controller = controller
            super.init()
            guard let state else { return }
            observation = Task { [weak self] in
                let results = Observations { () -> [SearchResultModel] in
                    _ = state.skipRevision
                    return state.searchResult
                }
                for await searchResults in results {
                    self?.controller?.updateNewSearchResults(searchResults)
                }
            }
            focusObservation = Task { [weak self] in
                for await shouldFocus in Observations({ state.shouldFocusResults }) where shouldFocus {
                    state.shouldFocusResults = false
                    self?.controller?.focusResults()
                }
            }
        }

        var observation: Task<Void, Never>?
        var focusObservation: Task<Void, Never>?
        var controller: FindNavigatorListViewController?

        isolated deinit {
            controller = nil
            observation?.cancel()
            observation = nil
            focusObservation?.cancel()
            focusObservation = nil
        }
    }
}
