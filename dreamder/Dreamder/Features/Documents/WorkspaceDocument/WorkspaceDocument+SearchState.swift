//
//  WorkspaceDocument+SearchState.swift
//  Dreamder
//
//  Created by Tom Ludwig on 16.01.24.
//

import Foundation
import Observation

extension WorkspaceDocument {
    @Observable
    @MainActor
    final class SearchState {
        enum IndexStatus: Equatable {
            case none
            case indexing(progress: Double)
            case done
        }

        enum FindNavigatorStatus: Equatable {
            case none
            case searching
            case replacing
            case found
            case replaced(updatedFiles: Int)
            case failed(errorMessage: String)
        }

        var searchResult: [SearchResultModel] = []
        var searchResultsFileCount: Int = 0
        var searchResultsCount: Int = 0
        /// Stores the user's input, shown when no files are found, and persists across navigation items.
        var searchQuery: String = ""
        var replaceText: String = ""

        var indexStatus: IndexStatus = .none

        var findNavigatorStatus: FindNavigatorStatus = .none

        var shouldFocusSearchField: Bool = false

        @ObservationIgnored weak var workspace: WorkspaceDocument?
        @ObservationIgnored var tempSearchResults = [SearchResultModel]()
        @ObservationIgnored var caseSensitive: Bool = false
        @ObservationIgnored var indexer: SearchIndexer?
        @ObservationIgnored var indexGeneration: Int = 0
        @ObservationIgnored var indexingTask: Task<Void, Never>?
        @ObservationIgnored var indexingNotificationID: String?
        @ObservationIgnored var selectedMode: [SearchModeModel] = [
            .Find,
            .Text,
            .Containing
        ]

        init(_ workspace: WorkspaceDocument) {
            self.workspace = workspace
            addProjectToIndex()
        }

        isolated deinit {
            indexingTask?.cancel()
        }

        var replaceOptions: NSString.CompareOptions {
            var options: NSString.CompareOptions = []

            if selectedMode.second == .RegularExpression {
                options.insert(.regularExpression)
            }

            if !caseSensitive {
                options.insert(.caseInsensitive)
            }

            return options
        }
    }
}
