//
//  WorkspaceDocument+FindAndReplace.swift
//  Dreamder
//
//  Created by Tommy Ludwig on 02.01.24.
//

import Foundation
import AppKit

extension WorkspaceDocument.SearchState {
    /// Performs a search and replace operation in a collection of files based on the provided query.
    ///
    /// - Parameters:
    ///   - query: The search query to look for in the files.
    ///   - replacingTerm: The term to replace the matched query with.
    ///
    /// - Important: This function relies on an indexer and assumes that it has been previously set.
    /// If the indexer is not available, the function will return early.
    /// Also make sure to flush any pending changes to the index before calling this function.
    func findAndReplace(query: String, replacingTerm: String) async throws {
        await setStatus(.replacing)

        let plan: FindPlan
        do {
            plan = try await makeFindPlan(query: query, replacement: replacingTerm)
            if plan.model.isRegularExpressions {
                try RegexReplacement.validate(template: replacingTerm, regex: plan.regex)
            }
        } catch let failure as FindFailure {
            await setStatus(.failed(errorMessage: failure.message))
            return
        } catch let error as RegexReplacement.TemplateError {
            await setStatus(.failed(errorMessage: FindFailure.invalidReplacement(error.message).message))
            return
        }

        var errorCount: Int = 0, updatedFilesCount: Int = 0

        await withTaskGroup(of: Bool?.self) { taskGroup in
            for candidate in plan.files {
                taskGroup.addTask { () -> Bool? in
                    try? await Self.replaceOccurrences(in: candidate.url, model: plan.model, regex: plan.regex)
                }
            }

            for await outcome in taskGroup {
                switch outcome {
                case .some(true): updatedFilesCount += 1
                case .some(false): break
                case .none: errorCount += 1
                }
            }
        }

        if updatedFilesCount == 0 && errorCount == 0 {
            await setStatus(.failed(errorMessage: "No files in the workspace matched: \(query)"))
        } else if updatedFilesCount == 0 && errorCount > 0 {
            await setStatus(
                .failed(
                    errorMessage: "All files failed to update. (\(errorCount)) " +
                    "errors occurred. Check logs for more information"
                )
            )
        } else if updatedFilesCount > 0 && errorCount > 0 {
            await setStatus(
                .failed(
                    errorMessage: "\(updatedFilesCount) successfully updated, " +
                    "\(errorCount) errors occurred. Please check logs for more information."
                )
            )
        } else {
            await setStatus(.replaced(updatedFiles: updatedFilesCount))
        }
    }

    /// Replaces occurrences of a specified query with a given replacement term in the content of a file.
    ///
    /// - Parameters:
    ///     - fileURL: The URL of the file to be processed.
    ///     - query:  The string to be searched for and replaced.
    ///     - replacingTerm: The string to replace occurrences of the query.
    ///     - options: The options for the search and replace operation.
    ///             You can use options such as regular expression or case-insensitivity.
    ///
    /// The function performs the replacement in memory and then writes the modified content back to the file
    func replaceOccurrencesInFile(
        fileURL: URL,
        query: String,
        replacingTerm: String
    ) async throws {
        let model = makeFindModel(query: query, replacement: replacingTerm)
        guard let regex = model.compileMatcher() else { throw FindFailure.invalidRegularExpression }
        _ = try await Self.replaceOccurrences(in: fileURL, model: model, regex: regex)
    }

    @concurrent
    static func replaceOccurrences(
        in fileURL: URL,
        model: FindModel,
        regex: NSRegularExpression
    ) async throws -> Bool {
        let data = try Data(contentsOf: fileURL)
        guard let content = String(bytes: data, encoding: .utf8) else { return false }
        let replacement = try model.replaceAll(in: content, using: regex)
        guard replacement.replacedCount > 0, replacement.text != content else { return false }
        try replacement.text.write(to: fileURL, atomically: true, encoding: .utf8)
        return true
    }

    /// Replaces a specified range of text within a file with a new string.
    ///
    /// - Parameters:
    ///   - file: The URL of the file to be modified.
    ///   - searchTerm: The string to be replaced within the specified range.
    ///   - replacingTerm: The string to replace the specified searchTerm.
    ///   - keywordRange: The range within which the replacement should occur.
    ///
    /// - Note: This function  can be utilised for two specific use cases:
    ///         1. To replace a particular occurrence of a string within a file,
    ///         provide the range of the keyword to be replaced.
    ///         2. To replace all occurrences of the string within the file,
    ///         pass the start and end index covering the entire range.
    func replaceRange(
        file: URL,
        searchTerm: String,
        replacingTerm: String,
        keywordRange: Range<String.Index>
    ) {
        guard let fileContent = try? String(contentsOf: file, encoding: .utf8) else {
            presentError("An error occurred while reading file contents of: \(file)")
            return
        }

        let model = makeFindModel(query: searchTerm, replacement: replacingTerm)
        guard let regex = model.compileMatcher() else {
            presentError(FindFailure.invalidRegularExpression.message)
            return
        }
        guard keywordRange.upperBound <= fileContent.endIndex else { return }

        do {
            let replacement = try model.replaceAll(
                in: fileContent,
                using: regex,
                range: NSRange(keywordRange, in: fileContent)
            )
            guard replacement.replacedCount > 0, replacement.text != fileContent else { return }
            try replacement.text.write(to: file, atomically: true, encoding: .utf8)
        } catch let error as RegexReplacement.TemplateError {
            presentError(FindFailure.invalidReplacement(error.message).message)
        } catch {
            presentError("An error occurred while writing to: \(error.localizedDescription)")
        }
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func setStatus(_ status: FindNavigatorStatus) async {
        await MainActor.run {
            self.findNavigatorStatus = status
        }
    }
}
