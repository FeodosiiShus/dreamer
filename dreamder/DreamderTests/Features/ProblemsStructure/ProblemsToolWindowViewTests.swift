import CodeEditSourceEditor
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ProblemsToolWindowViewTests {
    @MainActor
    private struct ProblemsFixture {
        let workspace: WorkspaceDocument
        let first: URL
        let second: URL
        let nested: URL
    }

    private func makeFixture(in dir: URL) throws -> ProblemsFixture {
        let nestedDirectory = dir.appending(path: "Sub")
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        let first = dir.appending(path: "First.swift")
        let second = dir.appending(path: "Second.swift")
        let nested = nestedDirectory.appending(path: "Nested.swift")
        for url in [first, second, nested] {
            try "one\ntwo\nthree\nfour\nfive\nsix\n".write(to: url, atomically: true, encoding: .utf8)
        }
        let workspace = try HostedViewFixture.makeWorkspace(in: dir)
        return ProblemsFixture(workspace: workspace, first: first, second: second, nested: nested)
    }

    private func diagnostic(
        _ url: URL,
        line: Int,
        column: Int = 0,
        severity: WorkspaceDiagnostic.Severity,
        message: String,
        source: String? = "swiftc"
    ) -> WorkspaceDiagnostic {
        WorkspaceDiagnostic(
            fileURL: url,
            startLine: line,
            startColumn: column,
            endLine: line,
            endColumn: column + 1,
            severity: severity,
            message: message,
            source: source,
            code: nil
        )
    }

    private func populate(_ fixture: ProblemsFixture) -> [WorkspaceDiagnostic] {
        let firstDiagnostics = [
            diagnostic(fixture.first, line: 0, severity: .error, message: "Expected declaration"),
            diagnostic(fixture.first, line: 1, column: 4, severity: .warning, message: "Unused variable", source: nil),
            diagnostic(fixture.first, line: 2, severity: .information, message: "Consider renaming", source: ""),
            diagnostic(fixture.first, line: 3, severity: .hint, message: "Can be simplified")
        ]
        fixture.workspace.diagnosticsStore.replace(firstDiagnostics, for: fixture.first)
        fixture.workspace.diagnosticsStore.replace(
            [diagnostic(fixture.second, line: 4, column: 1, severity: .error, message: "Missing return")],
            for: fixture.second
        )
        fixture.workspace.diagnosticsStore.replace(
            [diagnostic(fixture.nested, line: 5, severity: .warning, message: "Deprecated call")],
            for: fixture.nested
        )
        return firstDiagnostics
    }

    private func host(
        _ fixture: ProblemsFixture,
        model: ProblemsToolWindowModel
    ) throws -> HostedView {
        let store = fixture.workspace.diagnosticsStore
        return try HostedViewFixture.hostInWorkspace(fixture.workspace) {
            ProblemsToolWindowContent(store: store, lspService: LSPService(), model: model)
        }
    }

    private func cursor(of workspace: WorkspaceDocument) throws -> (url: URL, line: Int?, column: Int?) {
        let manager = try #require(workspace.editorManager)
        let tab = try #require(manager.activeEditor.selectedTab)
        return (
            tab.file.url.standardizedFileURL,
            tab.cursorPositions.first?.start.line,
            tab.cursorPositions.first?.start.column
        )
    }

    @Test
    func emptyStatesDescribeWhyThereAreNoProblems() async throws {
        try await withTempDir { dir in
            let fixture = try makeFixture(in: dir)
            defer { fixture.workspace.close() }
            let model = ProblemsToolWindowModel()
            let hosted = try host(fixture, model: model)
            defer { hosted.close() }

            try await hosted.settle()
            #expect(hosted.renders())
            let noFile = hosted.snapshot()

            model.tab = .project
            try await hosted.settle()
            let project = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(noFile, project))

            model.tab = .file
            EditorLocationNavigation.open(fileURL: fixture.first, line: 1, column: 1, workspace: fixture.workspace)
            try await hosted.settle()
            let withoutServer = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(noFile, withoutServer))
        }
    }

    @Test
    func fileTabListsTheActiveFilesDiagnosticsAndCollapses() async throws {
        try await withTempDir { dir in
            let fixture = try makeFixture(in: dir)
            defer { fixture.workspace.close() }
            _ = populate(fixture)
            EditorLocationNavigation.open(fileURL: fixture.first, line: 1, column: 1, workspace: fixture.workspace)
            let model = ProblemsToolWindowModel()
            let hosted = try host(fixture, model: model)
            defer { hosted.close() }

            try await hosted.settle()
            #expect(hosted.renders())
            let expanded = hosted.snapshot()

            model.toggleFile(fixture.first)
            #expect(model.collapsedFiles == [fixture.first])
            try await hosted.settle()
            let collapsed = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(expanded, collapsed))

            model.toggleFile(fixture.first)
            #expect(model.collapsedFiles.isEmpty)
            try await hosted.settle()
            #expect(HostedView.pixelsDiffer(collapsed, hosted.snapshot()))
        }
    }

    @Test
    func projectTabListsEveryFileWithItsDirectory() async throws {
        try await withTempDir { dir in
            let fixture = try makeFixture(in: dir)
            defer { fixture.workspace.close() }
            _ = populate(fixture)
            EditorLocationNavigation.open(fileURL: fixture.first, line: 1, column: 1, workspace: fixture.workspace)
            let model = ProblemsToolWindowModel()
            let hosted = try host(fixture, model: model)
            defer { hosted.close() }
            try await hosted.settle()
            let fileTab = hosted.snapshot()

            model.tab = .project
            try await hosted.settle()
            #expect(hosted.renders())
            #expect(HostedView.pixelsDiffer(fileTab, hosted.snapshot()))
        }
    }

    @Test
    func selectionRequestsFocusAndHighlightsTheRow() async throws {
        try await withTempDir { dir in
            let fixture = try makeFixture(in: dir)
            defer { fixture.workspace.close() }
            let diagnostics = populate(fixture)
            EditorLocationNavigation.open(fileURL: fixture.first, line: 1, column: 1, workspace: fixture.workspace)
            let model = ProblemsToolWindowModel()
            let hosted = try host(fixture, model: model)
            defer { hosted.close() }
            try await hosted.settle()
            let unselected = hosted.snapshot()
            #expect(model.selection == nil)
            #expect(model.focusRequests == 0)

            model.selectFile(fixture.first)
            #expect(model.selection == .file(fixture.first))
            #expect(model.focusRequests == 1)
            try await hosted.settle()
            let fileSelected = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(unselected, fileSelected))

            model.selectDiagnostic(diagnostics[0])
            #expect(model.selection == .diagnostic(diagnostics[0]))
            #expect(model.focusRequests == 2)
            try await hosted.settle()
            #expect(HostedView.pixelsDiffer(fileSelected, hosted.snapshot()))
        }
    }

    @Test
    func openingADiagnosticMovesTheEditorCaretToItsPosition() async throws {
        try withTempDir { dir in
            let fixture = try makeFixture(in: dir)
            defer { fixture.workspace.close() }
            _ = populate(fixture)
            let model = ProblemsToolWindowModel()
            let target = diagnostic(fixture.second, line: 4, column: 1, severity: .error, message: "Missing return")

            model.openDiagnostic(target, fileURL: fixture.second, workspace: fixture.workspace)

            #expect(model.selection == .diagnostic(target))
            let position = try cursor(of: fixture.workspace)
            #expect(position.url == fixture.second.standardizedFileURL)
            #expect(position.line == 5)
            #expect(position.column == 2)
        }
    }

    @Test
    func returnActivatesTheSelectedFileOrDiagnosticAndIgnoresAnEmptySelection() async throws {
        try withTempDir { dir in
            let fixture = try makeFixture(in: dir)
            defer { fixture.workspace.close() }
            let diagnostics = populate(fixture)
            let model = ProblemsToolWindowModel()

            #expect(model.activateSelection(workspace: fixture.workspace) == .handled)
            #expect(try #require(fixture.workspace.editorManager).activeEditor.selectedTab == nil)

            model.selectFile(fixture.nested)
            #expect(model.activateSelection(workspace: fixture.workspace) == .handled)
            let filePosition = try cursor(of: fixture.workspace)
            #expect(filePosition.url == fixture.nested.standardizedFileURL)
            #expect(filePosition.line == 1)
            #expect(filePosition.column == 1)

            model.selectDiagnostic(diagnostics[1])
            #expect(model.activateSelection(workspace: fixture.workspace) == .handled)
            let diagnosticPosition = try cursor(of: fixture.workspace)
            #expect(diagnosticPosition.url == fixture.first.standardizedFileURL)
            #expect(diagnosticPosition.line == 2)
            #expect(diagnosticPosition.column == 5)
        }
    }

    @Test
    func toggleFileSelectsAndCollapsesTheFile() {
        let model = ProblemsToolWindowModel()
        let url = URL(fileURLWithPath: "/project/A.swift")

        model.toggleFile(url)
        #expect(model.selection == .file(url))
        #expect(model.collapsedFiles == [url])
        #expect(model.focusRequests == 0)

        model.toggleCollapsed(url)
        #expect(model.collapsedFiles.isEmpty)
        model.toggleCollapsed(url)
        #expect(model.collapsedFiles == [url])
    }

    @Test
    func theToolWindowManagerShowsAndHidesTheHostedProblemsWindow() async throws {
        try await withTempDir { dir in
            let fixture = try makeFixture(in: dir)
            defer { fixture.workspace.close() }
            _ = populate(fixture)
            EditorLocationNavigation.open(fileURL: fixture.first, line: 1, column: 1, workspace: fixture.workspace)
            let manager = fixture.workspace.toolWindowManager

            manager.show(.problems)
            #expect(manager.isVisible(.problems))
            let hosted = try HostedViewFixture.hostInWorkspace(fixture.workspace) { ProblemsToolWindow() }
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())

            manager.hide(.problems)
            #expect(manager.isVisible(.problems) == false)
        }
    }

    @Test
    func severityTogglesFilterRowsAndCounts() async throws {
        try await withTempDir { dir in
            let fixture = try makeFixture(in: dir)
            defer { fixture.workspace.close() }
            _ = populate(fixture)
            let model = ProblemsToolWindowModel()
            model.tab = .project
            let hosted = try host(fixture, model: model)
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())
            let unfiltered = hosted.snapshot()

            model.toggleSeverity(.errors)
            #expect(model.severityFilter.isShown(.errors) == false)
            try await hosted.settle()
            let withoutErrors = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(unfiltered, withoutErrors))

            model.toggleSeverity(.warnings)
            model.toggleSeverity(.weakWarnings)
            try await hosted.settle()
            #expect(hosted.renders())
            #expect(HostedView.pixelsDiffer(withoutErrors, hosted.snapshot()))

            model.toggleSeverity(.errors)
            model.toggleSeverity(.warnings)
            model.toggleSeverity(.weakWarnings)
            try await hosted.settle()
            #expect(HostedView.pixelsDiffer(withoutErrors, hosted.snapshot()))
        }
    }

    @Test
    func projectTabPullsWorkspaceDiagnosticsOnlyWhenSelected() async throws {
        try await withTempDir { dir in
            let fixture = try makeFixture(in: dir)
            defer { fixture.workspace.close() }
            let model = ProblemsToolWindowModel()
            let puller = WorkspaceDiagnosticsPuller()
            let service = LSPService()

            await model.pullProjectDiagnostics(workspace: fixture.workspace, lspService: service, puller: puller)
            model.tab = .project
            await model.pullProjectDiagnostics(workspace: fixture.workspace, lspService: service, puller: puller)

            let hosted = try HostedViewFixture.hostInWorkspace(fixture.workspace) {
                ProblemsToolWindowContent(
                    store: fixture.workspace.diagnosticsStore,
                    lspService: service,
                    model: model,
                    puller: puller
                )
            }
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())
        }
    }
}
