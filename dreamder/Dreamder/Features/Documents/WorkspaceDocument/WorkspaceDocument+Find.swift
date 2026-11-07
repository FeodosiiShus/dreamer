//
//  WorkspaceDocument+Find.swift
//  Dreamder
//
//  Created by Tommy Ludwig on 02.01.24.
//

import Foundation

extension WorkspaceDocument.SearchState {
    /// Creates a search term based on the given query and search mode.
    ///
    /// - Parameter query: The original user query string.
    ///
    /// - Returns: A modified search term according to the specified search mode.
    func getSearchTerm(_ query: String) -> String {
        let newQuery = stripSpecialCharacters(from: (caseSensitive ? query : query.lowercased()))
        guard let mode = selectedMode.third, !wholeWordsOnly else {
            return newQuery
        }

        switch mode {
        case .Containing:
            return "*\(newQuery)*"
        case .StartingWith:
            return "\(newQuery)*"
        case .EndingWith:
            return "*\(newQuery)"
        default:
            return newQuery
        }
    }

    func stripSpecialCharacters(from string: String) -> String {
        let regex = try? NSRegularExpression(pattern: "[^a-zA-Z0-9]+", options: .caseInsensitive)
        guard let regex else { return string }
        return regex.stringByReplacingMatches(
            in: string,
            options: [],
            range: NSRange(location: 0, length: string.utf16.count),
            withTemplate: "*"
        )
    }

    /// Generates a regular expression pattern based on the specified query and search mode.
    ///
    /// - Parameter query: The original user query string.
    ///
    /// - Returns: A string representing the regular expression pattern based on the selected search mode.
    ///
    /// - Note: This function is creating similar patterns to the
    /// ``WorkspaceDocument/SearchState-swift.class/getSearchTerm(_:)`` function,
    /// Except its using the word boundary anchor(\b) instead of the asterisk(\*).
    /// This is needed to highlight the search results correctly.
    func getRegexPattern(_ query: String) -> String {
        if isRegularExpression {
            return query
        }

        let newQuery = NSRegularExpression.escapedPattern(for: query.trimmingCharacters(in: .whitespacesAndNewlines))

        guard let mode = selectedMode.third else {
            return newQuery
        }

        switch mode {
        case .Containing:
            return "\(newQuery)"
        case .StartingWith:
            return "\\b\(newQuery)"
        case .EndingWith:
            return "\(newQuery)\\b"
        case .MatchingWord:
            return "\\b\(newQuery)\\b"
        default:
            return newQuery
        }
    }

    /// Searches the entire workspace for the given string, using the
    /// ``WorkspaceDocument/SearchState-swift.class/selectedMode`` modifiers
    /// to modify the search if needed. This is done by filtering out files with SearchKit and then searching
    /// within each file for the given string.
    ///
    /// This method will update
    /// ``WorkspaceDocument/SearchState-swift.class/searchResult``,
    /// ``WorkspaceDocument/SearchState-swift.class/searchResultsFileCount``
    /// and ``WorkspaceDocument/SearchState-swift.class/searchResultCount`` with any matched
    /// search results. See ``SearchResultModel`` and ``SearchResultMatchModel``
    /// for more information on search results and matches.
    ///
    /// - Parameter query: The search query to search for.
    func search(_ query: String) async {
        await MainActor.run {
            self.searchQuery = query
            self.searchResult.removeAll()
            self.searchResultsCount = 0
            self.searchResultsFileCount = 0
            self.tempSearchResults = []
            self.findNavigatorStatus = .searching
        }

        guard !query.isEmpty else {
            await MainActor.run {
                self.setSearchResults()
            }
            return
        }

        let plan: FindPlan
        do {
            plan = try await makeFindPlan(query: query)
        } catch let failure as FindFailure {
            await setStatus(.failed(errorMessage: failure.message))
            return
        } catch {
            await setStatus(.failed(errorMessage: error.localizedDescription))
            return
        }

        await withTaskGroup(of: (URL, Float, FileEvaluation).self) { group in
            for candidate in plan.files {
                group.addTask {
                    let evaluation = Self.evaluateFile(at: candidate.url, model: plan.model, regex: plan.regex)
                    return (candidate.url, candidate.score, evaluation)
                }
            }

            for await (fileURL, fileScore, evaluation) in group where !evaluation.matches.isEmpty {
                let file = CEWorkspaceFile(url: fileURL)
                let newResult = SearchResultModel(file: file, score: fileScore)
                newResult.lineMatches = evaluation.matches.map {
                    SearchResultMatchModel(
                        rangeWithinFile: $0.rangeWithinFile,
                        file: file,
                        lineContent: $0.lineContent,
                        keywordRange: $0.keywordRange
                    )
                }
                appendNewResultsToTempResults(newResult: newResult)
            }
        }

        await MainActor.run {
            self.setSearchResults()
        }
    }

    /// Appends a new search result to the temporary search results array on the main thread.
    ///
    /// - Parameters:
    ///   - newResult: The `SearchResultModel` to be appended to the temporary search results.
    @MainActor
    func appendNewResultsToTempResults(newResult: SearchResultModel) {
        self.tempSearchResults.append(newResult)
    }

    /// Sets the search results by updating various properties on the main thread.
    /// This function updates `findNavigatorStatus`, `searchResult`, `searchResultCount`, and `searchResultsFileCount`
    /// and sets the `tempSearchResults` to an empty array.
    /// - Important: Call this function when you are ready to
    /// display or use the final search results.
    @MainActor
    func setSearchResults() {
        self.searchResult = self.tempSearchResults.sorted {
            $0.score == $1.score ? $0.file.url.path < $1.file.url.path : $0.score > $1.score
        }
        self.searchResultsCount = self.tempSearchResults.map { $0.lineMatches.count }.reduce(0, +)
        self.searchResultsFileCount = self.tempSearchResults.count
        self.findNavigatorStatus = .found
        self.tempSearchResults = []
    }

    nonisolated static func evaluateFile(
        at fileURL: URL,
        model: FindModel,
        regex: NSRegularExpression
    ) -> FileEvaluation {
        guard let data = try? Data(contentsOf: fileURL),
              let fileContent = String(bytes: data, encoding: .utf8) else {
            return FileEvaluation(matches: [])
        }

        let snapshots = model.findMatches(in: fileContent, using: regex).compactMap { match -> FileMatchSnapshot? in
            guard match.range.length > 0 else { return nil }
            return FileMatchSnapshot.make(matchRange: match.range, in: fileContent)
        }
        return FileEvaluation(matches: snapshots)
    }

    func makeFindPlan(query: String, replacement: String? = nil) async throws -> FindPlan {
        let model = makeFindModel(query: query, replacement: replacement)
        guard let regex = model.compileMatcher() else { throw FindFailure.invalidRegularExpression }
        let mask: FileMask
        do {
            mask = try FileMask(filter: model.fileFilter)
        } catch {
            throw FindFailure.invalidFileMask
        }
        guard let indexer else { throw FindFailure.noIndex }

        let indexTerm = model.isRegularExpressions || !Self.hasIndexableWords(query) ? nil : getSearchTerm(query)
        let files = await Self.candidateFiles(
            index: indexer,
            term: indexTerm,
            model: model,
            scope: model.makeScope(projectRoot: workspace?.fileURL),
            mask: mask
        )
        return FindPlan(model: model, regex: regex, files: files)
    }

    nonisolated static func hasIndexableWords(_ query: String) -> Bool {
        query.contains { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    @concurrent
    static func candidateFiles(
        index: SearchIndexer,
        term: String?,
        model: FindModel,
        scope: FindScope?,
        mask: FileMask
    ) async -> [FileCandidate] {
        var candidates: [FileCandidate] = []
        if let term {
            let searchStream = await SearchIndexer.AsyncManager(index: index).search(query: term, 20)
            for await chunk in searchStream {
                for file in chunk.results where model.accepts(file.url, scope: scope, mask: mask) {
                    candidates.append(FileCandidate(url: file.url, score: file.score))
                }
            }
        } else {
            for url in index.documents() where model.accepts(url, scope: scope, mask: mask) {
                candidates.append(FileCandidate(url: url, score: 0))
            }
        }
        return candidates
    }

    /// Resets the search results along with counts for overall results and file-specific results.
    func clearResults() {
        DispatchQueue.main.async {
            self.searchResult.removeAll()
            self.searchResultsCount = 0
            self.searchResultsFileCount = 0
            self.findNavigatorStatus = .none
        }
    }
}

nonisolated struct FileEvaluation: Sendable {
    let matches: [FileMatchSnapshot]
}

nonisolated struct FileCandidate: Sendable {
    let url: URL
    let score: Float
}

nonisolated struct FindPlan: Sendable {
    let model: FindModel
    let regex: NSRegularExpression
    let files: [FileCandidate]
}

nonisolated enum FindFailure: Error, Equatable, Sendable {
    case noIndex
    case invalidRegularExpression
    case invalidFileMask
    case invalidReplacement(String)

    var message: String {
        switch self {
        case .noIndex: "No index found. Try rebuilding the index."
        case .invalidRegularExpression: "Invalid regular expression."
        case .invalidFileMask: "Invalid file mask."
        case .invalidReplacement(let detail): "Invalid replacement string: \(detail)"
        }
    }
}
