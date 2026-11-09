//
//  IgnorePatternModel.swift
//  Dreamder
//
//  Created by Austin Condiff on 11/1/24.
//

import Foundation
import Observation
import os

/// A model to manage Git ignore patterns for a file, including loading, saving, and monitoring changes.
@Observable
@MainActor
final class IgnorePatternModel {
    /// Indicates whether patterns are currently being loaded from the Git ignore file.
    var loadingPatterns: Bool = false

    /// A collection of Git ignore patterns being managed by this model.
    var patterns: [GlobPattern] = [] {
        didSet {
            if !loadingPatterns {
                savePatterns()
            } else {
                loadingPatterns = false
            }
        }
    }

    /// Tracks the selected patterns by their unique identifiers (UUIDs).
    var selection: Set<UUID> = []

    /// A client for interacting with the Git configuration.
    private let gitConfig: GitConfigClient

    private let homeDirectory: URL

    init(
        gitConfig: GitConfigClient = GitConfigClient(shellClient: currentWorld.shellClient),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.gitConfig = gitConfig
        self.homeDirectory = homeDirectory
    }

    private static let logger = Logger(subsystem: "dev.dreamder.Dreamder", category: "IgnorePatternModel")

    /// A file system monitor for detecting changes to the Git ignore file.
    @ObservationIgnored private var fileMonitor: DispatchSourceFileSystemObject?

    /// Task tracking the current save operation
    @ObservationIgnored private var savingTask: Task<Void, Never>?

    func start() async {
        try? await startFileMonitor()
        await loadPatterns()
    }

    isolated deinit {
        stopFileMonitor()
    }

    /// Resolves the URL for the Git ignore file.
    /// - Returns: The resolved `URL` for the Git ignore file.
    private func gitIgnoreURL() async throws -> URL {
        let excludesFile = try await gitConfig.get(key: "core.excludesfile") ?? ""
        if !excludesFile.isEmpty {
            if excludesFile.starts(with: "~/") {
                let relativePath = String(excludesFile.dropFirst(2)) // Remove "~/"
                return homeDirectory.appending(path: relativePath)
            } else if excludesFile.starts(with: "/") {
                return URL(fileURLWithPath: excludesFile) // Absolute path
            } else {
                return homeDirectory.appending(path: excludesFile)
            }
        } else {
            let defaultPath = ".gitignore_global"
            let fileURL = homeDirectory.appending(path: defaultPath)
            await gitConfig.set(key: "core.excludesfile", value: "~/\(defaultPath)", global: true)
            return fileURL
        }
    }

    /// Starts monitoring the Git ignore file for changes.
    private func startFileMonitor() async throws {
        let fileURL = try await gitIgnoreURL()
        let fileDescriptor = open(fileURL.path, O_EVTONLY)
        guard fileDescriptor != -1 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: DispatchQueue.main
        )

        source.setEventHandler { [weak self] in
            Task { await self?.loadPatterns() }
        }

        source.setCancelHandler {
            close(fileDescriptor)
        }

        fileMonitor?.cancel()
        fileMonitor = source
        source.resume()
    }

    /// Stops monitoring the Git ignore file.
    private func stopFileMonitor() {
        fileMonitor?.cancel()
        fileMonitor = nil
    }

    /// Loads patterns from the Git ignore file into the `patterns` property.
    func loadPatterns() async {
        loadingPatterns = true

        do {
            let fileURL = try await gitIgnoreURL()
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                patterns = []
                loadingPatterns = false
                return
            }

            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                patterns = content.split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !$0.starts(with: "#") }
                    .map { GlobPattern(value: String($0)) }
                loadingPatterns = false
            } else {
                patterns = []
                loadingPatterns = false
            }
        } catch {
            Self.logger.error("Error loading patterns: \(error.localizedDescription, privacy: .public)")
            patterns = []
            loadingPatterns = false
        }
    }

    /// Retrieves the pattern associated with a specific UUID.
    /// - Parameter id: The UUID of the pattern to retrieve.
    /// - Returns: The matching `GlobPattern`, if found.
    func getPattern(for id: UUID) -> GlobPattern? {
        return patterns.first(where: { $0.id == id })
    }

    /// Saves the current patterns back to the Git ignore file.
    @MainActor
    func savePatterns() {
        // Cancel the existing task if it exists
        savingTask?.cancel()

        // Start a new task for saving patterns
        savingTask = Task {
            stopFileMonitor()
            defer {
                savingTask = nil // Clear the task when done
                Task { try? await startFileMonitor() }
            }

            do {
                let fileURL = try await gitIgnoreURL()
                guard let fileContent = try? String(contentsOf: fileURL, encoding: .utf8) else {
                    await writeAllPatterns()
                    return
                }

                let lines = fileContent.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                let (patternToLineIndex, nonPatternLines) = mapLines(lines)
                let globalCommentLines = extractGlobalComments(nonPatternLines, patternToLineIndex)

                var reorderedLines = reorderPatterns(globalCommentLines, patternToLineIndex, nonPatternLines, lines)

                // Ensure single blank line at the end
                reorderedLines = cleanUpWhitespace(in: reorderedLines)

                // Write the updated content back to the file
                let updatedContent = reorderedLines.joined(separator: "\n")
                try updatedContent.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                Self.logger.error("Error saving patterns: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Maps lines to patterns and non-pattern lines (e.g., comments or whitespace).
    private func mapLines(_ lines: [String]) -> ([String: Int], [(line: String, index: Int)]) {
        var patternToLineIndex: [String: Int] = [:]
        var nonPatternLines: [(line: String, index: Int)] = []

        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if !trimmedLine.isEmpty && !trimmedLine.hasPrefix("#") {
                patternToLineIndex[trimmedLine] = index
            } else if index != lines.count - 1 {
                nonPatternLines.append((line: line, index: index))
            }
        }

        return (patternToLineIndex, nonPatternLines)
    }

    /// Extracts global comments from the non-pattern lines.
    private func extractGlobalComments(
        _ nonPatternLines: [(line: String, index: Int)],
        _ patternToLineIndex: [String: Int]
    ) -> [String] {
        let globalComments = nonPatternLines.filter { $0.index < (patternToLineIndex.values.min() ?? Int.max) }
        return globalComments.map(\.line)
    }

    /// Reorders patterns while preserving associated comments and whitespace.
    private func reorderPatterns(
        _ globalCommentLines: [String],
        _ patternToLineIndex: [String: Int],
        _ nonPatternLines: [(line: String, index: Int)],
        _ lines: [String]
    ) -> [String] {
        var reorderedLines: [String] = globalCommentLines
        var usedNonPatternLines = Set<Int>()

        for pattern in patterns {
            let value = pattern.value

            // Insert the pattern
            reorderedLines.append(value)

            // Preserve associated non-pattern lines
            if let currentIndex = patternToLineIndex[value] {
                for nextIndex in (currentIndex + 1)..<lines.count {
                    if let nonPatternLine = nonPatternLines.first(where: { $0.index == nextIndex }),
                       !usedNonPatternLines.contains(nonPatternLine.index) {
                        reorderedLines.append(nonPatternLine.line)
                        usedNonPatternLines.insert(nonPatternLine.index)
                    } else {
                        break
                    }
                }
            }
        }

        // Retain non-pattern lines that follow deleted patterns
        for (line, index) in nonPatternLines {
            if !usedNonPatternLines.contains(index) && !reorderedLines.contains(line) {
                reorderedLines.append(line)
                usedNonPatternLines.insert(index)
            }
        }

        return reorderedLines
    }

    /// Writes all patterns to the Git ignore file.
    private func writeAllPatterns() async {
        do {
            let fileURL = try await gitIgnoreURL()
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }

            let content = patterns.map(\.value).joined(separator: "\n")
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            Self.logger.error("Failed to write all patterns: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Cleans up extra whitespace from lines.
    private func cleanUpWhitespace(in lines: [String]) -> [String] {
        var cleanedLines: [String] = []
        var previousLineWasBlank = false

        for line in lines {
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if !(isBlank && previousLineWasBlank) {
                cleanedLines.append(line)
            }
            previousLineWasBlank = isBlank
        }

        // Trim extra blank lines at the end, ensuring only a single blank line
        while let lastLine = cleanedLines.last, lastLine.trimmingCharacters(in: .whitespaces).isEmpty {
            cleanedLines.removeLast()
        }
        cleanedLines.append("") // Ensure exactly one blank line at the end

        // Trim whitespace at the top of the file
        while let firstLine = cleanedLines.first, firstLine.trimmingCharacters(in: .whitespaces).isEmpty {
            cleanedLines.removeFirst()
        }

        return cleanedLines
    }

    /// Adds a new, empty pattern to the list of patterns.
    func addPattern() {
        patterns.append(GlobPattern(value: ""))
    }

    /// Removes the specified patterns from the list of patterns.
    /// - Parameter selection: The set of UUIDs for the patterns to remove. If `nil`, no patterns are removed.
    func removePatterns(_ selection: Set<UUID>? = nil) {
        let patternsToRemove = selection?.compactMap { getPattern(for: $0) } ?? []
        patterns.removeAll { patternsToRemove.contains($0) }
        self.selection.removeAll()
    }
}
