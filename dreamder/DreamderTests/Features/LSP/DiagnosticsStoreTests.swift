import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct DiagnosticsStoreTests {
    private func diagnostic(
        _ path: String,
        line: Int,
        column: Int = 0,
        severity: WorkspaceDiagnostic.Severity,
        message: String = "message"
    ) -> WorkspaceDiagnostic {
        WorkspaceDiagnostic(
            fileURL: URL(fileURLWithPath: path),
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

    @Test
    func replaceSortsBySeverityThenPosition() {
        let store = DiagnosticsStore()
        let url = URL(fileURLWithPath: "/tmp/project/a.swift")
        store.replace([
            diagnostic(url.path, line: 9, severity: .warning),
            diagnostic(url.path, line: 3, column: 4, severity: .error),
            diagnostic(url.path, line: 3, column: 1, severity: .error),
            diagnostic(url.path, line: 1, severity: .hint)
        ], for: url)
        let ordered = store.diagnostics(for: url).map { "\($0.severity.rawValue):\($0.startLine):\($0.startColumn)" }
        #expect(ordered == ["1:3:1", "1:3:4", "2:9:0", "4:1:0"])
    }

    @Test
    func emptyReplacementRemovesTheFile() {
        let store = DiagnosticsStore()
        let url = URL(fileURLWithPath: "/tmp/project/a.swift")
        store.replace([diagnostic(url.path, line: 0, severity: .error)], for: url)
        store.replace([], for: url)
        #expect(store.files.isEmpty)
        #expect(store.diagnostics(for: url).isEmpty)
    }

    @Test
    func countsAggregateAcrossFiles() {
        let store = DiagnosticsStore()
        let first = URL(fileURLWithPath: "/tmp/project/a.swift")
        let second = URL(fileURLWithPath: "/tmp/project/b.swift")
        store.replace([
            diagnostic(first.path, line: 0, severity: .error),
            diagnostic(first.path, line: 1, severity: .warning)
        ], for: first)
        store.replace([
            diagnostic(second.path, line: 0, severity: .error),
            diagnostic(second.path, line: 2, severity: .information)
        ], for: second)
        #expect(store.errorCount == 2)
        #expect(store.warningCount == 1)
        #expect(store.files.map(\.lastPathComponent) == ["a.swift", "b.swift"])
    }

    @Test
    func equivalentPathsShareOneEntry() {
        let store = DiagnosticsStore()
        let canonical = URL(fileURLWithPath: "/tmp/project/a.swift")
        let dotted = URL(fileURLWithPath: "/tmp/project/sub/../a.swift")
        store.replace([diagnostic(canonical.path, line: 0, severity: .error)], for: dotted)
        #expect(store.diagnostics(for: canonical).count == 1)
        store.clear(canonical)
        #expect(store.files.isEmpty)
    }

    @Test
    func clearAllRemovesEverything() {
        let store = DiagnosticsStore()
        let url = URL(fileURLWithPath: "/tmp/project/a.swift")
        store.replace([diagnostic(url.path, line: 0, severity: .warning)], for: url)
        store.clearAll()
        #expect(store.errorCount == 0)
        #expect(store.warningCount == 0)
        #expect(store.files.isEmpty)
    }
}
