import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct FindScopeFilterTests {
    private func found(
        _ query: String,
        in dir: URL,
        configure: (FindStateSupport.State) -> Void = { _ in }
    ) async throws -> [String] {
        let (workspace, state) = try await FindStateSupport.prepare(in: dir)
        defer { workspace.close() }
        configure(state)
        await state.search(query)
        return FindStateSupport.relativePaths(of: state, in: dir)
    }

    @Test
    func defaultExcludedDirectoriesNeverAppear() async throws {
        try await withTempDir { dir in
            for path in [
                "node_modules/pkg/x.js", ".git/hooks/x.txt", ".build/x.txt", "build/x.txt", "dist/x.txt", "Pods/x.txt",
                "src/kept.txt"
            ] {
                try FindStateSupport.write("needle\n", path, in: dir)
            }

            let paths = try await found("needle", in: dir)

            #expect(paths == ["src/kept.txt"])
        }
    }

    @Test
    func gitignoredFilesAreExcluded() async throws {
        try await withTempDir { dir in
            try FindStateSupport.write("ignored/\n*.log\nsecret.txt\n", ".gitignore", in: dir)
            for path in ["ignored/a.txt", "debug.log", "secret.txt", "sub/secret.txt", "kept.txt", "sub/kept.txt"] {
                try FindStateSupport.write("needle\n", path, in: dir)
            }

            let paths = try await found("needle", in: dir)

            #expect(paths == ["kept.txt", "sub/kept.txt"])
        }
    }

    @Test
    func binaryNulLargeAndNonUtf8FilesNeverAppear() async throws {
        try await withTempDir { dir in
            try FindStateSupport.write("needle\n", "ok.txt", in: dir)
            try FindStateSupport.write("needle\n", "image.png", in: dir)
            try FindStateSupport.writeData(Data("needle".utf8) + Data([0]) + Data("tail".utf8), "nul.txt", in: dir)
            try FindStateSupport.writeData(
                Data("needle ".utf8) + Data(repeating: 0x61, count: WorkspaceFileScope.maxIndexableTextSize + 1),
                "huge.txt",
                in: dir
            )
            try FindStateSupport.writeData(Data("needle ".utf8) + Data([0xFF, 0xFE, 0xE9]), "latin.txt", in: dir)

            let paths = try await found("needle", in: dir)

            #expect(paths == ["ok.txt"])
        }
    }

    @Test
    func directoryScopeWithSubdirectories() async throws {
        try await withTempDir { dir in
            for path in ["src/a.txt", "src/deep/b.txt", "other/c.txt", "root.txt"] {
                try FindStateSupport.write("needle\n", path, in: dir)
            }

            let absolute = try await found("needle", in: dir) { state in
                state.findModel.isProjectScope = false
                state.directoryScopePath = dir.appending(path: "src").path
            }
            let relative = try await found("needle", in: dir) { state in
                state.findModel.isProjectScope = false
                state.directoryScopePath = "src"
            }

            #expect(absolute == ["src/a.txt", "src/deep/b.txt"])
            #expect(relative == ["src/a.txt", "src/deep/b.txt"])
        }
    }

    @Test
    func directoryScopeWithoutSubdirectories() async throws {
        try await withTempDir { dir in
            for path in ["src/a.txt", "src/deep/b.txt", "other/c.txt", "root.txt"] {
                try FindStateSupport.write("needle\n", path, in: dir)
            }

            let paths = try await found("needle", in: dir) { state in
                state.findModel.isProjectScope = false
                state.findModel.isWithSubdirectories = false
                state.directoryScopePath = dir.appending(path: "src").path
            }

            #expect(paths == ["src/a.txt"])
        }
    }

    @Test
    func projectScopeIgnoresTheDirectoryField() async throws {
        try await withTempDir { dir in
            for path in ["src/a.txt", "root.txt"] {
                try FindStateSupport.write("needle\n", path, in: dir)
            }

            let paths = try await found("needle", in: dir) { state in
                state.findModel.isProjectScope = true
                state.directoryScopePath = "src"
            }

            #expect(paths == ["root.txt", "src/a.txt"])
        }
    }

    @Test
    func fileMaskIncludesAndExcludesByName() async throws {
        try await withTempDir { dir in
            for path in ["A.swift", "ATests.swift", "b.txt", "c.md"] {
                try FindStateSupport.write("needle\n", path, in: dir)
            }

            let swiftOnly = try await found("needle", in: dir) { $0.fileMask = "*.swift, !*Tests.swift" }
            let several = try await found("needle", in: dir) { $0.fileMask = "*.txt,*.md" }
            let onlyExclusion = try await found("needle", in: dir) { $0.fileMask = "!*.swift" }

            #expect(swiftOnly == ["A.swift"])
            #expect(several == ["b.txt", "c.md"])
            #expect(onlyExclusion == ["b.txt", "c.md"])
        }
    }

    @Test
    func invalidRegularExpressionFails() async throws {
        try await withTempDir { dir in
            try FindStateSupport.write("needle\n", "a.txt", in: dir)
            let (workspace, state) = try await FindStateSupport.prepare(in: dir)
            defer { workspace.close() }
            state.isRegularExpression = true

            await state.search("Ips(")

            #expect(state.findNavigatorStatus == .failed(errorMessage: "Invalid regular expression."))
            #expect(state.searchResult.isEmpty)
            #expect(state.searchResultsCount == 0)
        }
    }

    @Test
    func searchWithoutAnOpenProjectFails() async throws {
        try await withTempDir { dir in
            try FindStateSupport.write("needle\n", "a.txt", in: dir)
            let (workspace, state) = try await FindStateSupport.prepare(in: dir)
            defer { workspace.close() }
            workspace.tearDownFileScope()

            await state.search("needle")

            #expect(state.findNavigatorStatus == .failed(errorMessage: "No project is open."))
            #expect(state.searchResult.isEmpty)
        }
    }

    @Test
    func emptyQueryFindsNothing() async throws {
        try await withTempDir { dir in
            try FindStateSupport.write("needle\n", "a.txt", in: dir)
            let (workspace, state) = try await FindStateSupport.prepare(in: dir)
            defer { workspace.close() }
            await state.search("needle")
            #expect(state.searchResultsCount == 1)

            await state.search("")

            #expect(state.findNavigatorStatus == .found)
            #expect(state.searchQuery.isEmpty)
            #expect(state.searchResult.isEmpty)
            #expect(state.searchResultsCount == 0)
            #expect(state.searchResultsFileCount == 0)
        }
    }

    @Test
    func caseSensitiveOptionNarrowsTheMatches() async throws {
        try await withTempDir { dir in
            try FindStateSupport.write("needle Needle NEEDLE\n", "a.txt", in: dir)
            let (workspace, state) = try await FindStateSupport.prepare(in: dir)
            defer { workspace.close() }

            await state.search("needle")
            #expect(state.searchResultsCount == 3)

            state.caseSensitive = true
            await state.search("needle")
            #expect(state.searchResultsCount == 1)
        }
    }

    @Test
    func wholeWordsOptionSkipsPartialWords() async throws {
        try await withTempDir { dir in
            try FindStateSupport.write("needle needles reneedle\n", "a.txt", in: dir)
            let (workspace, state) = try await FindStateSupport.prepare(in: dir)
            defer { workspace.close() }

            await state.search("needle")
            #expect(state.searchResultsCount == 3)

            state.wholeWordsOnly = true
            await state.search("needle")
            #expect(state.searchResultsCount == 1)
        }
    }

    @Test
    func regularExpressionOptionMatchesPatterns() async throws {
        try await withTempDir { dir in
            try FindStateSupport.write("needle nedle neddle\n", "a.txt", in: dir)
            let (workspace, state) = try await FindStateSupport.prepare(in: dir)
            defer { workspace.close() }
            state.isRegularExpression = true

            await state.search("ne+dle")

            #expect(state.findNavigatorStatus == .found)
            #expect(state.searchResultsCount == 2)
        }
    }

    @Test
    func multilineQueriesMatchAcrossLines() async throws {
        try await withTempDir { dir in
            try FindStateSupport.write("one\ntwo\nthree\n", "a.txt", in: dir)
            let (workspace, state) = try await FindStateSupport.prepare(in: dir)
            defer { workspace.close() }

            await state.search("one\ntwo")

            #expect(state.searchResultsCount == 1)
            let match = try #require(FindStateSupport.matches("a.txt", in: state).first)
            #expect(match.lineContent == "one⏎two")
            #expect(match.usage?.range == NSRange(location: 0, length: 7))
        }
    }

    @Test
    func dirtyOpenDocumentIsSearchedInsteadOfTheDisk() async throws {
        try await withTempDir { dir in
            let fixture = try HostedSourceEditorFixture.make(
                in: dir,
                fileName: "dirty.txt",
                typeIdentifier: "public.plain-text",
                contents: "disk haystack\n"
            )
            let (workspace, state) = try await FindStateSupport.prepare(in: dir)
            defer { workspace.close() }
            fixture.editorInstance.file.fileDocument = fixture.document
            let editor = try #require(workspace.editorManager?.activeEditor)
            editor.tabs.append(fixture.editorInstance)
            try await eventually { fixture.document.content != nil }
            let storage = try #require(fixture.document.content)
            storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: "unsaved needle\n")
            fixture.document.updateChangeCount(.changeDone)

            await state.search("needle")
            #expect(FindStateSupport.relativePaths(of: state, in: dir) == ["dirty.txt"])
            #expect(FindStateSupport.matches("dirty.txt", in: state).first?.lineContent == "unsaved needle")

            await state.search("haystack")
            #expect(state.searchResult.isEmpty)
            #expect(state.findNavigatorStatus == .found)

            withExtendedLifetime(fixture) {}
        }
    }

    @Test
    func cleanOpenDocumentIsSearchedOnDisk() async throws {
        try await withTempDir { dir in
            let fixture = try HostedSourceEditorFixture.make(
                in: dir,
                fileName: "clean.txt",
                typeIdentifier: "public.plain-text",
                contents: "disk haystack\n"
            )
            let (workspace, state) = try await FindStateSupport.prepare(in: dir)
            defer { workspace.close() }
            fixture.editorInstance.file.fileDocument = fixture.document
            let editor = try #require(workspace.editorManager?.activeEditor)
            editor.tabs.append(fixture.editorInstance)
            try await eventually { fixture.document.content != nil }
            let storage = try #require(fixture.document.content)
            storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: "buffer needle\n")
            #expect(!fixture.document.isDocumentEdited)

            await state.search("needle")
            #expect(state.searchResult.isEmpty)

            await state.search("haystack")
            #expect(FindStateSupport.relativePaths(of: state, in: dir) == ["clean.txt"])

            withExtendedLifetime(fixture) {}
        }
    }
}
