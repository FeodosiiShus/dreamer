//
//  WorkspaceDocument+FindAndReplace.swift
//  Dreamder
//
//  Created by Tommy Ludwig on 02.01.24.
//

import Foundation

extension WorkspaceDocument.SearchState {
    nonisolated struct ReplaceReport: Equatable, Sendable {
        var updatedFiles = 0
        var errors = 0

        mutating func record(_ outcome: FindReplaceOutcome) {
            if case .replaced = outcome {
                updatedFiles += 1
            }
            if !outcome.isClean {
                errors += 1
            }
        }

        var failureMessage: String? {
            guard errors > 0 else { return nil }
            if updatedFiles == 0 {
                return "All files failed to update. (\(errors)) errors occurred. Check logs for more information"
            }
            return "\(updatedFiles) successfully updated, " +
                "\(errors) errors occurred. Please check logs for more information."
        }
    }

    enum ResultSelection: Equatable {
        case file(SearchResultModel)
        case match(SearchResultMatchModel)
    }

    struct ReplaceSelection {
        let result: SearchResultModel
        let ranges: [NSRange]

        init(result: SearchResultModel, matches: [SearchResultMatchModel]) {
            self.result = result
            self.ranges = matches.compactMap { $0.isSkipped ? nil : $0.usage?.range }
        }
    }

    func cancelPreviewRefresh() {
        previewRefreshTask?.cancel()
        previewRefreshTask = nil
    }

    func replaceAll() async {
        cancelPreviewRefresh()
        if findNavigatorStatus != .found {
            await search(searchQuery)
        }
        await replace(searchResult.map { ReplaceSelection(result: $0, matches: $0.lineMatches) })
    }

    func replace(_ match: SearchResultMatchModel) async {
        guard let result = searchResult.first(where: { $0.lineMatches.contains { $0 === match } }) else { return }
        match.isSkipped = false
        await replace([ReplaceSelection(result: result, matches: [match])])
    }

    func replaceInFile(_ result: SearchResultModel) async {
        await replace([ReplaceSelection(result: result, matches: result.lineMatches)])
    }

    func replaceSelected() async {
        switch resultSelection {
        case .match(let match):
            await replace(match)
        case .file(let result):
            await replaceInFile(result)
        case nil:
            break
        }
    }

    func toggleSkip(_ match: SearchResultMatchModel) {
        match.isSkipped.toggle()
        skipRevision += 1
    }

    func toggleSkip(_ result: SearchResultModel) {
        let skip = result.lineMatches.contains { !$0.isSkipped }
        result.lineMatches.forEach { $0.isSkipped = skip }
        skipRevision += 1
    }

    func toggleSkipSelected() {
        switch resultSelection {
        case .match(let match):
            toggleSkip(match)
        case .file(let result):
            toggleSkip(result)
        case nil:
            break
        }
    }

    func performReplacements(_ jobs: [FindReplaceJob]) async -> [FindReplaceOutcome] {
        let documents = openDocuments()
        var outcomes = [FindReplaceOutcome](repeating: .stale, count: jobs.count)
        var diskIndices: [Int] = []
        var diskJobs: [FindReplaceJob] = []
        for (index, job) in jobs.enumerated() {
            if let document = documents[job.url.workspacePathKey] {
                outcomes[index] = FindBufferReplacer.apply(job, to: document)
            } else {
                diskIndices.append(index)
                diskJobs.append(job)
            }
        }
        for (index, outcome) in zip(diskIndices, await FindFileRewriter.rewrite(diskJobs)) {
            outcomes[index] = outcome
        }
        return outcomes
    }

    private func replace(_ selections: [ReplaceSelection]) async {
        cancelPreviewRefresh()
        let work = selections.filter { !$0.ranges.isEmpty }
        guard !work.isEmpty, var model = resultsModel, let regex = resultsRegex else { return }
        model.stringToReplace = replaceText
        model.isPreserveCase = findModel.isPreserveCase
        if let issue = Self.replacementIssue(for: model, regex: regex) {
            replaceNotice = FindFailure.invalidReplacement(issue).message
            return
        }

        let jobs = work.map { FindReplaceJob(url: $0.result.file.url, ranges: $0.ranges, model: model, regex: regex) }
        let generation = searchGeneration
        let outcomes = await performReplacements(jobs)
        guard isCurrentSearch(generation) else { return }

        var report = ReplaceReport()
        for (selection, outcome) in zip(work, outcomes) {
            report.record(outcome)
            switch outcome {
            case .replaced(let result):
                update(selection.result, selected: Set(selection.ranges), outcome: result)
            case .stale:
                removeMatches(in: selection.result, at: Set(selection.ranges))
            case .failed:
                break
            }
        }
        finishReplacement(report)
    }

    private func removeMatches(in result: SearchResultModel, at ranges: Set<NSRange>) {
        result.lineMatches.removeAll { match in match.usage.map { ranges.contains($0.range) } ?? false }
    }

    private func update(_ result: SearchResultModel, selected: Set<NSRange>, outcome: FindReplaceResult) {
        let lines = FindLineIndex(outcome.text)
        result.lineMatches = result.lineMatches.compactMap { match in
            guard let usage = match.usage, !selected.contains(usage.range) else { return nil }
            let delta = FindReplaceEngine.delta(before: usage.range.location, applied: outcome.applied)
            let moved = usage.moved(by: delta, lines: lines)
            guard let snapshot = FileMatchSnapshot.make(matchRange: moved.range, in: outcome.text) else { return nil }
            let rebased = SearchResultMatchModel(
                rangeWithinFile: snapshot.rangeWithinFile,
                file: match.file,
                lineContent: snapshot.lineContent,
                keywordRange: snapshot.keywordRange,
                usage: moved
            )
            rebased.isSkipped = match.isSkipped
            return rebased
        }
    }

    private func finishReplacement(_ report: ReplaceReport) {
        cancelPreviewRefresh()
        searchResult = searchResult.filter { !$0.lineMatches.isEmpty }
        searchResultsFileCount = searchResult.count
        searchResultsCount = searchResult.reduce(0) { $0 + $1.lineMatches.count }
        resultSelection = nil
        replaceNotice = report.failureMessage
        if searchResult.isEmpty {
            findNavigatorStatus = report.failureMessage.map { .failed(errorMessage: $0) }
                ?? .replaced(updatedFiles: report.updatedFiles)
        } else {
            findNavigatorStatus = .found
        }
    }
}
