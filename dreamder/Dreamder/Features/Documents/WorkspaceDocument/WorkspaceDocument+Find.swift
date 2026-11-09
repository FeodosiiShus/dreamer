//
//  WorkspaceDocument+Find.swift
//  Dreamder
//
//  Created by Tommy Ludwig on 02.01.24.
//

import Foundation

extension WorkspaceDocument.SearchState {
    /// Generates a regular expression pattern based on the specified query and search mode.
    ///
    /// - Parameter query: The original user query string.
    ///
    /// - Returns: A string representing the regular expression pattern based on the selected search mode.
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

    func search(_ query: String) async {
        searchTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        let task = Task { await self.performSearch(query, generation: generation) }
        searchTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func performSearch(_ query: String, generation: Int) async {
        guard isCurrentSearch(generation) else { return }
        searchQuery = query
        resetResults()
        guard !query.isEmpty else {
            setSearchResults()
            return
        }

        let plan: FindPlan
        do {
            plan = try await makeFindPlan(query: query, previewsReplacements: selectedMode.isReplaceMode)
        } catch {
            guard isCurrentSearch(generation) else { return }
            let failure = (error as? FindFailure)?.message ?? error.localizedDescription
            findNavigatorStatus = .failed(errorMessage: failure)
            return
        }
        guard isCurrentSearch(generation) else { return }
        replacementError = plan.replacementIssue
        resultsModel = plan.model
        resultsRegex = plan.regex

        for await hit in Self.hits(for: plan) {
            guard isCurrentSearch(generation) else { return }
            accept(hit)
        }
        guard isCurrentSearch(generation) else { return }
        setSearchResults()
    }

    func isCurrentSearch(_ generation: Int) -> Bool {
        searchGeneration == generation
    }

    private func resetResults() {
        flushTask?.cancel()
        flushTask = nil
        lastFlush = nil
        searchResult = []
        searchResultsCount = 0
        searchResultsFileCount = 0
        tempSearchResults = []
        replaceNotice = nil
        replacementError = nil
        resultSelection = nil
        findNavigatorStatus = .searching
    }

    private func accept(_ hit: FileHit) {
        let file = CEWorkspaceFile(url: hit.url)
        let result = SearchResultModel(file: file, score: hit.score)
        result.lineMatches = hit.evaluation.hits.map {
            SearchResultMatchModel(
                rangeWithinFile: $0.snapshot.rangeWithinFile,
                file: file,
                lineContent: $0.snapshot.lineContent,
                keywordRange: $0.snapshot.keywordRange,
                usage: $0.usage
            )
        }
        tempSearchResults.append(result)
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        let generation = searchGeneration
        let due = lastFlush.map { $0 + self.flushInterval }
        guard let due, ContinuousClock.now < due else {
            publishPartialResults()
            return
        }
        flushTask = Task { [weak self] in
            try? await Task.sleep(until: due, clock: .continuous)
            guard !Task.isCancelled, let self, self.isCurrentSearch(generation) else { return }
            self.publishPartialResults()
        }
    }

    private func publishPartialResults() {
        flushTask = nil
        lastFlush = .now
        publish(tempSearchResults)
    }

    private func publish(_ results: [SearchResultModel]) {
        searchResult = results.sorted {
            $0.score == $1.score ? $0.file.url.path < $1.file.url.path : $0.score > $1.score
        }
        searchResultsCount = results.reduce(0) { $0 + $1.lineMatches.count }
        searchResultsFileCount = results.count
    }

    func setSearchResults() {
        flushTask?.cancel()
        flushTask = nil
        publish(tempSearchResults)
        findNavigatorStatus = .found
        tempSearchResults = []
    }

    func clearResults() {
        searchTask?.cancel()
        searchGeneration += 1
        flushTask?.cancel()
        flushTask = nil
        searchResult.removeAll()
        searchResultsCount = 0
        searchResultsFileCount = 0
        tempSearchResults = []
        replaceNotice = nil
        replacementError = nil
        resultSelection = nil
        resultsModel = nil
        resultsRegex = nil
        findNavigatorStatus = .none
    }

    nonisolated static func evaluateFile(
        at fileURL: URL,
        model: FindModel,
        regex: NSRegularExpression,
        withReplacements: Bool = false,
        unsavedText: String? = nil
    ) -> FileEvaluation {
        guard let content = unsavedText ?? FindFileReader.text(at: fileURL) else {
            return .empty
        }

        let nsContent = content as NSString
        let lines = FindLineIndex(content)
        let hits = model.findMatches(in: content, using: regex).compactMap { match -> FileEvaluation.Hit? in
            guard match.range.length > 0,
                  let snapshot = FileMatchSnapshot.make(matchRange: match.range, in: content) else { return nil }
            let usage = FindUsage.make(
                for: match,
                in: nsContent,
                lines: lines,
                model: model,
                regex: regex,
                withReplacement: withReplacements
            )
            return FileEvaluation.Hit(snapshot: snapshot, usage: usage)
        }
        return FileEvaluation(hits: hits)
    }

    func makeFindPlan(
        query: String,
        previewsReplacements: Bool = false,
        makeMask: (String?) throws -> FileMask = { try FileMask(filter: $0) }
    ) async throws -> FindPlan {
        let model = makeFindModel(query: query)
        guard let regex = model.compileMatcher() else { throw FindFailure.invalidRegularExpression }
        let mask: FileMask
        do {
            mask = try makeMask(model.fileFilter)
        } catch {
            throw FindFailure.invalidFileMask
        }
        guard let fileScope = workspace?.fileScope else { throw FindFailure.noProject }

        let candidates = await fileScope.enumerateFiles(limit: nil)
        let files = await Self.candidateFiles(
            from: candidates,
            model: model,
            scope: model.makeScope(projectRoot: workspace?.fileURL),
            mask: mask
        )

        let replacementIssue = previewsReplacements ? Self.replacementIssue(for: model, regex: regex) : nil
        let withReplacements = previewsReplacements && replacementIssue == nil
        let unsaved = unsavedTexts()
        let override = fileEvaluationOverride
        let evaluate: @Sendable (URL) async -> FileEvaluation = { url in
            if let override, let evaluation = await override(url) {
                return evaluation
            }
            return Self.evaluateFile(
                at: url,
                model: model,
                regex: regex,
                withReplacements: withReplacements,
                unsavedText: unsaved[url.workspacePathKey]
            )
        }
        return FindPlan(
            model: model,
            regex: regex,
            files: files,
            replacementIssue: replacementIssue,
            evaluate: evaluate
        )
    }

    nonisolated static func replacementIssue(for model: FindModel, regex: NSRegularExpression) -> String? {
        guard model.isRegularExpressions else { return nil }
        do {
            try RegexReplacement.validate(template: model.stringToReplace, regex: regex)
            return nil
        } catch {
            return (error as? RegexReplacement.TemplateError)?.message ?? error.localizedDescription
        }
    }

    func openDocuments() -> [String: CodeFileDocument] {
        var documents: [String: CodeFileDocument] = [:]
        for file in workspace?.editorManager?.editorLayout.gatherOpenFiles() ?? [] {
            if let document = file.fileDocument, document.content != nil {
                documents[file.url.workspacePathKey] = document
            }
        }
        return documents
    }

    private func unsavedTexts() -> [String: String] {
        openDocuments().compactMapValues { $0.isDocumentEdited ? $0.content?.string : nil }
    }

    @concurrent
    static func candidateFiles(
        from urls: [URL],
        model: FindModel,
        scope: FindScope?,
        mask: FileMask
    ) async -> [FileCandidate] {
        urls
            .filter { model.accepts($0, scope: scope, mask: mask) }
            .map { FileCandidate(url: $0, score: 0) }
    }

    nonisolated static func fileHit(
        for candidate: FileCandidate,
        evaluate: @Sendable (URL) async -> FileEvaluation
    ) async -> FileHit? {
        let evaluation = await evaluate(candidate.url)
        guard !evaluation.hits.isEmpty else { return nil }
        return FileHit(url: candidate.url, score: candidate.score, evaluation: evaluation)
    }

    nonisolated static func hits(for plan: FindPlan) -> AsyncStream<FileHit> {
        AsyncStream { continuation in
            let producer = Task {
                await withTaskGroup(of: FileHit?.self) { group in
                    var pending = plan.files.makeIterator()
                    let width = max(2, ProcessInfo.processInfo.activeProcessorCount)
                    let evaluate = plan.evaluate
                    for _ in 0..<width {
                        guard let candidate = pending.next() else { break }
                        group.addTask { await fileHit(for: candidate, evaluate: evaluate) }
                    }
                    for await hit in group {
                        if Task.isCancelled {
                            group.cancelAll()
                            break
                        }
                        if let hit {
                            continuation.yield(hit)
                        }
                        if let candidate = pending.next() {
                            group.addTask { await fileHit(for: candidate, evaluate: evaluate) }
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }
}
