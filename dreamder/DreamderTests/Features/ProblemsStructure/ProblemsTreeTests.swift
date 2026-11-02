import Foundation
import Testing
@testable import Dreamder

@Suite
struct ProblemsTreeTests {
    private func diagnostic(
        file: String = "/project/Sources/File.swift",
        line: Int,
        column: Int = 0,
        severity: WorkspaceDiagnostic.Severity,
        message: String,
        source: String? = "swift",
        code: String? = nil
    ) -> WorkspaceDiagnostic {
        WorkspaceDiagnostic(
            fileURL: URL(fileURLWithPath: file),
            startLine: line,
            startColumn: column,
            endLine: line,
            endColumn: column + 1,
            severity: severity,
            message: message,
            source: source,
            code: code
        )
    }

    @Test
    func countsGroupSeverities() {
        let counts = ProblemCounts.of([
            diagnostic(line: 0, severity: .error, message: "a"),
            diagnostic(line: 1, severity: .error, message: "b"),
            diagnostic(line: 2, severity: .warning, message: "c"),
            diagnostic(line: 3, severity: .information, message: "d"),
            diagnostic(line: 4, severity: .hint, message: "e")
        ])
        #expect(counts.errors == 2)
        #expect(counts.warnings == 1)
        #expect(counts.information == 2)
        #expect(counts.total == 5)
    }

    @Test
    func countsSummaryReadsLikeIntelliJ() {
        let counts = ProblemCounts(errors: 1, warnings: 2, information: 0)
        #expect(counts.summary == "1 error, 2 warnings")
        #expect(ProblemCounts().summary.isEmpty)
    }

    @Test
    func instancesAreSortedByDirectoryThenName() throws {
        let root = URL(fileURLWithPath: "/project")
        let nodes = ProblemsTreeBuilder.instances(
            diagnosticsByFile: [
                URL(fileURLWithPath: "/project/Sources/B.swift"): [diagnostic(
                    file: "/project/Sources/B.swift", line: 0, severity: .error, message: "b"
                )],
                URL(fileURLWithPath: "/project/A.swift"): [diagnostic(
                    file: "/project/A.swift", line: 0, severity: .error, message: "a"
                )],
                URL(fileURLWithPath: "/project/Sources/A.swift"): [diagnostic(
                    file: "/project/Sources/A.swift", line: 0, severity: .warning, message: "c"
                )]
            ],
            root: root
        )
        #expect(nodes.map(\.name) == ["A.swift", "A.swift", "B.swift"])
        #expect(nodes.map(\.directory) == ["", "Sources", "Sources"])
    }

    @Test
    func emptyFilesAreDropped() {
        let nodes = ProblemsTreeBuilder.instances(
            diagnosticsByFile: [
                URL(fileURLWithPath: "/project/A.swift"): [],
                URL(fileURLWithPath: "/project/B.swift"): [diagnostic(
                    file: "/project/B.swift", line: 0, severity: .error, message: "b"
                )]
            ],
            root: URL(fileURLWithPath: "/project")
        )
        #expect(nodes.count == 1)
        #expect(nodes.first?.name == "B.swift")
    }

    @Test
    func diagnosticsAreSortedBySeverityThenPosition() throws {
        let node = try #require(ProblemsTreeBuilder.node(
            url: URL(fileURLWithPath: "/project/A.swift"),
            diagnostics: [
                diagnostic(file: "/project/A.swift", line: 9, severity: .warning, message: "w"),
                diagnostic(file: "/project/A.swift", line: 4, column: 7, severity: .error, message: "late"),
                diagnostic(file: "/project/A.swift", line: 4, column: 1, severity: .error, message: "early")
            ],
            root: URL(fileURLWithPath: "/project")
        ))
        #expect(node.diagnostics.map(\.message) == ["early", "late", "w"])
        #expect(node.counts.errors == 2)
        #expect(node.counts.warnings == 1)
    }

    @Test
    func relativeDirectoryIsEmptyOutsideTheProject() {
        let root = URL(fileURLWithPath: "/project")
        #expect(ProblemsTreeBuilder.relativeDirectory(
            of: URL(fileURLWithPath: "/project/A.swift"),
            root: root
        ) == "")
        #expect(ProblemsTreeBuilder.relativeDirectory(
            of: URL(fileURLWithPath: "/project/Sources/Deep/A.swift"),
            root: root
        ) == "Sources/Deep")
        #expect(ProblemsTreeBuilder.relativeDirectory(
            of: URL(fileURLWithPath: "/elsewhere/A.swift"),
            root: root
        ) == "")
        #expect(ProblemsTreeBuilder.relativeDirectory(
            of: URL(fileURLWithPath: "/project2/A.swift"),
            root: root
        ) == "")
        #expect(ProblemsTreeBuilder.relativeDirectory(
            of: URL(fileURLWithPath: "/project/A.swift"),
            root: nil
        ) == "")
    }

    @Test
    func locationIsOneBased() {
        let item = diagnostic(line: 0, column: 0, severity: .error, message: "x")
        #expect(ProblemsTreeBuilder.location(for: item) == "1:1")
        let second = diagnostic(line: 12, column: 4, severity: .warning, message: "y")
        #expect(ProblemsTreeBuilder.location(for: second) == "13:5")
    }

    @Test
    func tabTitlesShowCountsOnlyWhenPresent() {
        #expect(ProblemsTab.file.title(count: 0) == "File")
        #expect(ProblemsTab.file.title(count: 3) == "File (3)")
        #expect(ProblemsTab.project.baseTitle == "Project Errors")
        #expect(ProblemsTab.project.title(count: 2) == "Project Errors (2)")
    }

    @Test
    func emptyStatesMentionTheMissingLanguageServer() {
        #expect(ProblemsEmptyState.file(hasLanguageServer: true).secondary == nil)
        #expect(
            ProblemsEmptyState.file(hasLanguageServer: false).secondary
                == "No language server is running for this file"
        )
        #expect(
            ProblemsEmptyState.file(hasLanguageServer: false, hasActiveFile: false).secondary
                == "Open a file to see its problems"
        )
        #expect(ProblemsEmptyState.project.primary == "No problems found")
    }

    @Test
    func severitiesMapToIntelliJIcons() {
        #expect(WorkspaceDiagnostic.Severity.error.iconName == "status/error")
        #expect(WorkspaceDiagnostic.Severity.warning.iconName == "status/warning")
        #expect(WorkspaceDiagnostic.Severity.information.iconName == "status/info")
        #expect(WorkspaceDiagnostic.Severity.hint.iconName == "status/infoOutline")
    }
}
