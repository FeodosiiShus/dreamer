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
        var replaceNotice: String?
        var replacementError: String?
        var resultSelection: ResultSelection?
        var shouldFocusResults: Bool = false
        var skipRevision: Int = 0

        var findModel = FindModel()
        var selectedMode: [SearchModeModel] = [
            .Find,
            .Text,
            .Containing
        ]

        nonisolated struct PreviewInputs: Equatable, Sendable {
            let replaceText: String
            let preservesCase: Bool
            let isReplaceMode: Bool
        }

        @ObservationIgnored var flushInterval: Duration = .milliseconds(100)
        static let previewRefreshDelay: Duration = .milliseconds(300)

        @ObservationIgnored weak var workspace: WorkspaceDocument?
        @ObservationIgnored var tempSearchResults = [SearchResultModel]()
        @ObservationIgnored var indexer: SearchIndexer?
        @ObservationIgnored var indexGeneration: Int = 0
        @ObservationIgnored var indexingTask: Task<Void, Never>?
        @ObservationIgnored var indexingNotificationID: String?
        @ObservationIgnored var notificationCenter: NotificationCenter = .default
        @ObservationIgnored var searchTask: Task<Void, Never>?
        @ObservationIgnored var searchGeneration: Int = 0
        @ObservationIgnored var flushTask: Task<Void, Never>?
        @ObservationIgnored var lastFlush: ContinuousClock.Instant?
        @ObservationIgnored var previewObservation: Task<Void, Never>?
        @ObservationIgnored var previewRefreshTask: Task<Void, Never>?
        @ObservationIgnored var fileEvaluationOverride: (@Sendable (URL) async -> FileEvaluation?)?
        @ObservationIgnored var resultsModel: FindModel?
        @ObservationIgnored var resultsRegex: NSRegularExpression?

        init(_ workspace: WorkspaceDocument) {
            self.workspace = workspace
            addProjectToIndex()
            observePreviewInputs()
        }

        isolated deinit {
            indexingTask?.cancel()
            searchTask?.cancel()
            flushTask?.cancel()
            previewObservation?.cancel()
            previewRefreshTask?.cancel()
        }

        var previewInputs: PreviewInputs {
            PreviewInputs(
                replaceText: replaceText,
                preservesCase: findModel.isPreserveCase,
                isReplaceMode: selectedMode.isReplaceMode
            )
        }

        private func observePreviewInputs() {
            previewObservation = Task { [weak self] in
                var last = self?.previewInputs
                let inputs = Observations { [weak self] in self?.previewInputs }
                for await current in inputs where current != last {
                    last = current
                    self?.schedulePreviewRefresh()
                }
            }
        }

        func schedulePreviewRefresh() {
            cancelPreviewRefresh()
            guard selectedMode.isReplaceMode, findNavigatorStatus == .found, !searchQuery.isEmpty else { return }
            previewRefreshTask = Task { [weak self] in
                try? await Task.sleep(for: Self.previewRefreshDelay)
                guard !Task.isCancelled, let self else { return }
                await self.search(self.searchQuery)
            }
        }

        func setReplaceMode(_ replace: Bool) {
            let kind: SearchModeModel = replace ? .Replace : .Find
            guard let second = selectedMode.second, kind.children.contains(second) else {
                selectedMode = [kind, .Text, .Containing]
                return
            }
            selectedMode[0] = kind
        }

        var caseSensitive: Bool {
            get { findModel.isCaseSensitive }
            set { findModel.isCaseSensitive = newValue }
        }

        var isRegularExpression: Bool {
            get { selectedMode.isRegularExpressionMode }
            set {
                guard newValue != selectedMode.isRegularExpressionMode else { return }
                selectedMode = selectedMode.switchingRegularExpression(newValue)
            }
        }

        var wholeWordsOnly: Bool {
            get { findModel.isWholeWordsOnly || selectedMode.matchingMode == .MatchingWord }
            set {
                findModel.isWholeWordsOnly = newValue
                if !newValue, selectedMode.matchingMode == .MatchingWord {
                    selectedMode = selectedMode.switchingMatchingMode(.Containing)
                }
            }
        }

        var directoryScopePath: String {
            get { findModel.directoryName ?? "" }
            set { findModel.directoryName = newValue.isEmpty ? nil : newValue }
        }

        var fileMask: String {
            get { findModel.fileFilter ?? "" }
            set { findModel.fileFilter = newValue.isEmpty ? nil : newValue }
        }

        var scopeDescription: String {
            guard !findModel.isProjectScope, let directory = findModel.directoryName, !directory.isEmpty else {
                return "Project"
            }
            return directory
        }

        func makeFindModel(query: String, replacement: String? = nil) -> FindModel {
            var model = findModel
            model.initStringToFind(query)
            model.stringToReplace = replacement ?? replaceText
            model.isReplaceState = selectedMode.isReplaceMode
            model.isRegularExpressions = isRegularExpression
            model.isWholeWordsOnly = !isRegularExpression && wholeWordsOnly
            model.textAnchor = isRegularExpression ? .anywhere : Self.textAnchor(for: selectedMode.matchingMode)
            return model
        }

        private static func textAnchor(for mode: SearchModeModel?) -> FindModel.TextAnchor {
            guard let mode else { return .anywhere }
            if mode == .StartingWith { return .wordStart }
            if mode == .EndingWith { return .wordEnd }
            return .anywhere
        }
    }
}
