import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ProblemsCommandsCoverageTests {
    private func diagnostic(_ url: URL, line: Int, message: String) -> WorkspaceDiagnostic {
        WorkspaceDiagnostic(
            fileURL: url,
            startLine: line,
            startColumn: 0,
            endLine: line,
            endColumn: 1,
            severity: .error,
            message: message,
            source: nil,
            code: nil
        )
    }

    private func makeFiles(in directory: URL) throws -> (first: URL, second: URL) {
        let first = directory.appending(path: "A.swift")
        let second = directory.appending(path: "B.swift")
        for url in [first, second] {
            try "one\ntwo\nthree\nfour\n".write(to: url, atomically: true, encoding: .utf8)
        }
        return (first, second)
    }

    @Test
    func itemsAreDisabledWithoutAWorkspace() throws {
        let menu = CommandsACoverageSupport.host {
            ProblemsMenuContent(workspace: nil)
        }
        defer { menu.close() }

        #expect(menu.titles == ["Next Problem", "Previous Problem"])
        #expect(menu.enabledStates == [false, false])
        try menu.click(0)
        try menu.click(1)
        #expect(menu.items.count == 2)
    }

    @Test
    func itemsAreDisabledWhileTheWorkspaceHasNoProblems() throws {
        try withTempDir { directory in
            _ = try makeFiles(in: directory)
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let menu = CommandsACoverageSupport.host {
                ProblemsMenuContent(workspace: workspace)
            }
            defer { menu.close() }

            #expect(menu.enabledStates == [false, false])
        }
    }

    @Test
    func nextAndPreviousItemsMoveTheCaretBetweenProblems() throws {
        try withTempDir { directory in
            let files = try makeFiles(in: directory)
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            workspace.diagnosticsStore.replace([diagnostic(files.first, line: 1, message: "a")], for: files.first)
            workspace.diagnosticsStore.replace([diagnostic(files.second, line: 2, message: "b")], for: files.second)
            let menu = CommandsACoverageSupport.host {
                ProblemsMenuContent(workspace: workspace)
            }
            defer { menu.close() }

            #expect(menu.enabledStates == [true, true])

            try menu.click(titled: "Next Problem")
            let firstTab = try #require(workspace.editorManager?.activeEditor.selectedTab)
            #expect(firstTab.file.url.standardizedFileURL == files.first.standardizedFileURL)
            #expect(firstTab.cursorPositions.first?.start.line == 2)

            try menu.click(titled: "Next Problem")
            let secondTab = try #require(workspace.editorManager?.activeEditor.selectedTab)
            #expect(secondTab.file.url.standardizedFileURL == files.second.standardizedFileURL)
            #expect(secondTab.cursorPositions.first?.start.line == 3)

            try menu.click(titled: "Previous Problem")
            let backTab = try #require(workspace.editorManager?.activeEditor.selectedTab)
            #expect(backTab.file.url.standardizedFileURL == files.first.standardizedFileURL)
        }
    }

    @Test
    func commandBodyBuildsWithoutAWindowController() {
        _ = ProblemsCommands().body
    }
}
