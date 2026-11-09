import Foundation
import Testing
@testable import Dreamder

@Suite
struct ProblemsTreeCoverageTests {
    private func diagnostic(
        file: String,
        line: Int,
        severity: WorkspaceDiagnostic.Severity,
        message: String
    ) -> WorkspaceDiagnostic {
        WorkspaceDiagnostic(
            fileURL: URL(fileURLWithPath: file),
            startLine: line,
            startColumn: 0,
            endLine: line,
            endColumn: 1,
            severity: severity,
            message: message,
            source: nil,
            code: nil
        )
    }

    @Test
    func summaryNamesEverySeverityWithSingularAndPluralForms() {
        #expect(ProblemCounts(errors: 1, warnings: 2, information: 1).summary == "1 error, 2 warnings, 1 weak warning")
        #expect(ProblemCounts(errors: 2, warnings: 1, information: 3).summary == "2 errors, 1 warning, 3 weak warnings")
        #expect(ProblemCounts(errors: 0, warnings: 0, information: 2).summary == "2 weak warnings")
        #expect(ProblemCounts().summary.isEmpty)
    }

    @Test
    func fileNodesIdentifyThemselvesByUrlAndCountTheirDiagnostics() throws {
        let url = URL(fileURLWithPath: "/project/A.swift")
        let node = try #require(ProblemsTreeBuilder.node(
            url: url,
            diagnostics: [
                diagnostic(file: url.path, line: 0, severity: .error, message: "e"),
                diagnostic(file: url.path, line: 1, severity: .hint, message: "h")
            ],
            root: nil
        ))
        #expect(node.id == url)
        #expect(node.counts == ProblemCounts(errors: 1, warnings: 0, information: 1))
        #expect(node.counts.total == 2)
    }

    @Test
    func equalDirectoryAndNameFallBackToThePathOrder() {
        let first = URL(fileURLWithPath: "/a/x.swift")
        let second = URL(fileURLWithPath: "/b/x.swift")
        let byFile = [
            second: [diagnostic(file: second.path, line: 0, severity: .error, message: "second")],
            first: [diagnostic(file: first.path, line: 0, severity: .error, message: "first")]
        ]
        #expect(ProblemsTreeBuilder.instances(diagnosticsByFile: byFile, root: nil).map(\.url) == [first, second])
    }

    @Test
    func sameDirectoryOrdersByNameAndDifferentDirectoriesByDirectory() {
        let root = URL(fileURLWithPath: "/project")
        let urls = [
            URL(fileURLWithPath: "/project/Sources/b.swift"),
            URL(fileURLWithPath: "/project/Sources/a.swift"),
            URL(fileURLWithPath: "/project/Docs/z.swift")
        ]
        var byFile: [URL: [WorkspaceDiagnostic]] = [:]
        for url in urls {
            byFile[url] = [diagnostic(file: url.path, line: 0, severity: .warning, message: "w")]
        }
        let ordered = ProblemsTreeBuilder.instances(diagnosticsByFile: byFile, root: root)
        #expect(ordered.map(\.name) == ["z.swift", "a.swift", "b.swift"])
        #expect(ordered.map(\.directory) == ["Docs", "Sources", "Sources"])
    }
}
