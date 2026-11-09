import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct SearchEverywhereWorkspaceTests {
    private func makeWorkspace(_ dir: URL, files: [String: String]) throws -> WorkspaceDocument {
        for (path, text) in files { try touch(dir, path, text) }
        let workspace = WorkspaceDocument()
        try workspace.read(from: dir, ofType: "")
        return workspace
    }

    private func ignoredProject() -> [String: String] {
        let body = "class SharedName {}\n// marker-needle\n"
        return [
            ".gitignore": "ignored/\n",
            "Sources/Visible.swift": body,
            "ignored/Visible.swift": body,
            "node_modules/pkg/Visible.swift": body,
            "build/Visible.swift": body
        ]
    }

    @Test
    func workspaceOwnsOneSharedScopeAndIndex() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir, files: ["Sources/A.swift": "class Alpha {}\n"])
            defer { workspace.tearDownFileScope() }

            let scope = try #require(workspace.fileScope)
            let index = try #require(workspace.symbolIndex)
            #expect(workspace.openQuicklyViewModel?.scope === scope)

            let first = SearchEverywhereViewModel(workspace: workspace)
            let second = SearchEverywhereViewModel(workspace: workspace)
            #expect(first.symbolIndex === index)
            #expect(second.symbolIndex === index)

            first.start(on: .classes)
            first.query = "Alpha"
            try await eventually { first.flatItems.contains { $0.title == "Alpha" } }
            #expect(second.symbolIndex?.symbols.isEmpty == false)
            #expect(!second.isIndexing)

            workspace.tearDownFileScope()
            #expect(workspace.fileScope == nil)
            #expect(workspace.symbolIndex == nil)
        }
    }

    @Test
    func ignoredAndExcludedPathsNeverAppearInFileClassOrTextResults() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir, files: ignoredProject())
            defer { workspace.tearDownFileScope() }

            let files = SearchEverywhereViewModel(workspace: workspace)
            files.start(on: .files)
            files.query = "Visible"
            try await eventually { !files.flatItems.isEmpty }
            #expect(files.flatItems.map(\.detail) == ["Sources"])

            let classes = SearchEverywhereViewModel(workspace: workspace)
            classes.start(on: .classes)
            classes.query = "SharedName"
            try await eventually { !classes.flatItems.isEmpty }
            #expect(classes.flatItems.map(\.detail) == ["Sources/Visible.swift:1"])

            let text = SearchEverywhereViewModel(workspace: workspace)
            text.start(on: .text)
            text.query = "marker-needle"
            try await eventually { !text.flatItems.isEmpty }
            #expect(text.flatItems.map(\.detail) == ["Sources/Visible.swift:2"])
        }
    }

    @Test
    func aFileCreatedAfterOpenAppearsInFileResults() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir, files: ["Sources/Existing.swift": "class Existing {}\n"])
            defer { workspace.tearDownFileScope() }
            let model = SearchEverywhereViewModel(workspace: workspace)
            model.start(on: .files)
            model.query = "Existing"
            try await eventually { model.flatItems.count == 1 }
            try await Task.sleep(for: .milliseconds(300))

            try touch(dir, "Sources/ExistingTwo.swift", "class ExistingTwo {}\n")

            try await eventually { model.flatItems.map(\.title).sorted() == ["Existing.swift", "ExistingTwo.swift"] }
        }
    }

    @Test
    func aSymbolCreatedAfterOpenAppearsInClassResults() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir, files: ["Sources/Existing.swift": "class Existing {}\n"])
            defer { workspace.tearDownFileScope() }
            let model = SearchEverywhereViewModel(workspace: workspace)
            model.start(on: .classes)
            model.query = "Fresh"
            try await eventually { !model.isIndexing && model.symbolIndex?.symbols.isEmpty == false }
            try await Task.sleep(for: .milliseconds(300))

            try touch(dir, "Sources/Fresh.swift", "class FreshType {}\n")

            try await eventually { model.flatItems.contains { $0.title == "FreshType" } }
        }
    }

    @Test
    func aModelWithoutAWorkspaceHasNothingToSearch() async throws {
        let model = SearchEverywhereViewModel(workspace: nil)
        model.start(on: .files)
        model.query = "anything"
        try await Task.sleep(for: .milliseconds(400))
        #expect(model.flatItems.isEmpty)
        #expect(!model.isIndexing)
        #expect(model.symbolIndex == nil)

        model.selectTab(.classes)
        model.selectTab(.text)
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.flatItems.isEmpty)
    }

    @Test
    func resultsOfASupersededQueryNeverOverwriteTheNewOne() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir, files: [
                "Sources/Alpha.swift": "class Alpha {}\n",
                "Sources/Beta.swift": "class Beta {}\n"
            ])
            defer { workspace.tearDownFileScope() }
            let model = SearchEverywhereViewModel(workspace: workspace)
            model.start(on: .all)

            model.query = "Alpha"
            model.query = "Beta"
            try await eventually { model.flatItems.contains { $0.title == "Beta.swift" } }
            try await Task.sleep(for: .milliseconds(300))

            #expect(!model.flatItems.contains { $0.title == "Alpha.swift" })
        }
    }
}
