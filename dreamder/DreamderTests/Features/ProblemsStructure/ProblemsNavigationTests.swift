import CodeEditSourceEditor
import Foundation
import Testing
@testable import Dreamder

private func problem(
    _ file: String,
    line: Int,
    column: Int = 0,
    severity: WorkspaceDiagnostic.Severity = .error,
    message: String = "m"
) -> WorkspaceDiagnostic {
    WorkspaceDiagnostic(
        fileURL: URL(fileURLWithPath: file),
        startLine: line,
        startColumn: column,
        endLine: line,
        endColumn: column + 1,
        severity: severity,
        message: message,
        source: nil,
        code: nil
    )
}

@Suite
struct ProblemsSeverityFilterTests {
    private let all = [
        problem("/p/A.swift", line: 0, severity: .error),
        problem("/p/A.swift", line: 1, severity: .warning),
        problem("/p/A.swift", line: 2, severity: .information),
        problem("/p/A.swift", line: 3, severity: .hint)
    ]

    @Test func groupsMapSeverities() {
        #expect(ProblemSeverityGroup.group(of: .error) == .errors)
        #expect(ProblemSeverityGroup.group(of: .warning) == .warnings)
        #expect(ProblemSeverityGroup.group(of: .information) == .weakWarnings)
        #expect(ProblemSeverityGroup.group(of: .hint) == .weakWarnings)
        #expect(ProblemSeverityGroup.allCases.map(\.title) == ["Errors", "Warnings", "Weak Warnings and Hints"])
        #expect(ProblemSeverityGroup.allCases.map(\.iconName) == ["status/error", "status/warning", "status/info"])
        #expect(ProblemSeverityGroup.errors.id == "errors")
    }

    @Test func togglingHidesAndRestoresAGroup() {
        let filter = ProblemsSeverityFilter().toggling(.warnings)
        #expect(!filter.isShown(.warnings))
        #expect(!filter.isShown(WorkspaceDiagnostic.Severity.warning))
        #expect(filter.isShown(.errors))
        #expect(filter.apply(to: all).count == 3)
        #expect(filter.toggling(.warnings) == ProblemsSeverityFilter())
        #expect(ProblemsSeverityFilter().apply(to: all) == all)
    }

    @Test func countsReflectTheFilterAndEmptyFilesVanish() {
        let byFile = [
            URL(fileURLWithPath: "/p/A.swift"): all,
            URL(fileURLWithPath: "/p/B.swift"): [problem("/p/B.swift", line: 0, severity: .warning)]
        ]
        let root = URL(fileURLWithPath: "/p")
        let filter = ProblemsSeverityFilter().toggling(.warnings).toggling(.weakWarnings)
        let nodes = ProblemsTreeBuilder.instances(diagnosticsByFile: byFile, root: root, filter: filter)

        #expect(nodes.map(\.name) == ["A.swift"])
        #expect(nodes[0].counts.total == 1)
        let fileB = URL(fileURLWithPath: "/p/B.swift")
        #expect(ProblemsTreeBuilder.node(
            url: fileB, diagnostics: byFile[fileB] ?? [], root: root, filter: filter
        ) == nil)
    }

    @Test func diagnosticsSortBySeverityThenPosition() {
        let sorted = ProblemsTreeBuilder.sort([
            problem("/p/A.swift", line: 1, severity: .warning, message: "w"),
            problem("/p/A.swift", line: 5, severity: .error, message: "e5"),
            problem("/p/A.swift", line: 2, column: 3, severity: .error, message: "e2b"),
            problem("/p/A.swift", line: 2, column: 1, severity: .error, message: "e2a")
        ])
        #expect(sorted.map(\.message) == ["e2a", "e2b", "e5", "w"])
    }
}

@Suite
struct ProblemsNavigationTests {
    private let a1 = problem("/p/A.swift", line: 1, message: "a1")
    private let a5 = problem("/p/A.swift", line: 5, message: "a5")
    private let a3w = problem("/p/A.swift", line: 3, severity: .warning, message: "a3w")
    private let b2 = problem("/p/B.swift", line: 2, message: "b2")

    private var ordered: [WorkspaceDiagnostic] { [a1, a5, a3w, b2] }

    private func caret(_ file: String, _ line: Int, _ column: Int = 0) -> ProblemCaret {
        ProblemCaret(fileURL: URL(fileURLWithPath: file), line: line, column: column)
    }

    @Test func orderedFlattensNodesInTreeOrder() {
        let nodes = ProblemsTreeBuilder.instances(
            diagnosticsByFile: [
                URL(fileURLWithPath: "/p/B.swift"): [b2],
                URL(fileURLWithPath: "/p/A.swift"): [a3w, a5, a1]
            ],
            root: URL(fileURLWithPath: "/p")
        )
        #expect(ProblemsNavigation.ordered(nodes).map(\.message) == ["a1", "a5", "a3w", "b2"])
    }

    @Test func emptyListHasNoTarget() {
        #expect(ProblemsNavigation.target(.next, in: [], from: nil) == nil)
    }

    @Test func withoutACaretNextIsFirstAndPreviousIsLast() {
        #expect(ProblemsNavigation.target(.next, in: ordered, from: nil) == a1)
        #expect(ProblemsNavigation.target(.previous, in: ordered, from: nil) == b2)
    }

    @Test func aCaretInAFileWithoutProblemsStartsAtTheEnds() {
        #expect(ProblemsNavigation.target(.next, in: ordered, from: caret("/p/C.swift", 0)) == a1)
        #expect(ProblemsNavigation.target(.previous, in: ordered, from: caret("/p/C.swift", 0)) == b2)
    }

    @Test func aCaretOnAProblemMovesToTheNeighbourInTreeOrderAndWraps() {
        #expect(ProblemsNavigation.target(.next, in: ordered, from: caret("/p/A.swift", 1)) == a5)
        #expect(ProblemsNavigation.target(.next, in: ordered, from: caret("/p/B.swift", 2)) == a1)
        #expect(ProblemsNavigation.target(.previous, in: ordered, from: caret("/p/A.swift", 1)) == b2)
        #expect(ProblemsNavigation.target(.previous, in: ordered, from: caret("/p/B.swift", 2)) == a3w)
    }

    @Test func aCaretBetweenProblemsPicksTheNearestByPositionInTheFile() {
        #expect(ProblemsNavigation.target(.next, in: ordered, from: caret("/p/A.swift", 2)) == a3w)
        #expect(ProblemsNavigation.target(.previous, in: ordered, from: caret("/p/A.swift", 4)) == a3w)
        #expect(ProblemsNavigation.target(.next, in: ordered, from: caret("/p/A.swift", 1, 4)) == a3w)
    }

    @Test func leavingTheFileContinuesWithTheNextOrPreviousFileAndWraps() {
        #expect(ProblemsNavigation.target(.next, in: ordered, from: caret("/p/A.swift", 9)) == b2)
        #expect(ProblemsNavigation.target(.previous, in: ordered, from: caret("/p/A.swift", 0)) == b2)
        #expect(ProblemsNavigation.target(.next, in: ordered, from: caret("/p/B.swift", 9)) == a1)
        #expect(ProblemsNavigation.target(.previous, in: ordered, from: caret("/p/B.swift", 0)) == a3w)
    }
}

@MainActor
@Suite(.uiGate)
struct ProblemsNavigatorTests {
    private func makeFiles(in dir: URL) throws -> (URL, URL) {
        let first = dir.appending(path: "A.swift")
        let second = dir.appending(path: "B.swift")
        for url in [first, second] {
            try "one\ntwo\nthree\nfour\nfive\nsix\n".write(to: url, atomically: true, encoding: .utf8)
        }
        return (first, second)
    }

    @Test func navigatesAcrossFilesOpeningTheFileAtThePositionAndWraps() async throws {
        try withTempDir { dir in
            let (first, second) = try makeFiles(in: dir)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let store = workspace.diagnosticsStore
            store.replace([problem(first.path, line: 1, column: 2, message: "a")], for: first)
            store.replace([problem(second.path, line: 3, message: "b")], for: second)

            #expect(ProblemsNavigator.hasProblems(workspace: workspace))
            #expect(ProblemsNavigator.caret(in: workspace) == nil)

            #expect(ProblemsNavigator.navigate(.next, workspace: workspace)?.message == "a")
            let tab = try #require(workspace.editorManager?.activeEditor.selectedTab)
            #expect(tab.file.url.standardizedFileURL == first.standardizedFileURL)
            #expect(tab.cursorPositions.first?.start.line == 2)
            #expect(tab.cursorPositions.first?.start.column == 3)
            #expect(ProblemsNavigator.caret(in: workspace)?.line == 1)

            #expect(ProblemsNavigator.navigate(.next, workspace: workspace)?.message == "b")
            #expect(workspace.editorManager?.activeEditor.selectedTab?.file.url.standardizedFileURL
                == second.standardizedFileURL)
            #expect(ProblemsNavigator.navigate(.next, workspace: workspace)?.message == "a")
            #expect(ProblemsNavigator.navigate(.previous, workspace: workspace)?.message == "b")

            let errorsHidden = ProblemsSeverityFilter().toggling(.errors)
            #expect(ProblemsNavigator.navigate(.next, workspace: workspace, filter: errorsHidden) == nil)
        }
    }

    @Test func missingWorkspaceOrProblemsDoNothing() async throws {
        #expect(ProblemsNavigator.navigate(.next, workspace: nil) == nil)
        #expect(!ProblemsNavigator.hasProblems(workspace: nil))
        try withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            #expect(!ProblemsNavigator.hasProblems(workspace: workspace))
            #expect(ProblemsNavigator.navigate(.previous, workspace: workspace) == nil)
        }
    }

    @Test func unknownCaretPositionsAreIgnored() async throws {
        try withTempDir { dir in
            let (first, _) = try makeFiles(in: dir)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            EditorLocationNavigation.open(fileURL: first, line: 1, column: 1, workspace: workspace)
            workspace.editorManager?.activeEditor.selectedTab?.cursorPositions = [CursorPosition(range: NSRange(location: 0, length: 0))]
            #expect(ProblemsNavigator.caret(in: workspace) == nil)
        }
    }
}
