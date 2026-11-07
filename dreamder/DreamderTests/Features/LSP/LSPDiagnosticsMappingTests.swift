import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite("LSP diagnostics mapping")
struct LSPDiagnosticsMappingTests {
    private let fileURL = URL(fileURLWithPath: "/tmp/project/Sources/main.swift")

    private func diagnostic(
        line: Int = 2,
        character: Int = 4,
        endLine: Int = 2,
        endCharacter: Int = 12,
        severity: DiagnosticSeverity? = .error,
        code: DiagnosticCode? = nil
    ) -> Diagnostic {
        Diagnostic(
            range: LSPRange(
                start: Position(line: line, character: character),
                end: Position(line: endLine, character: endCharacter)
            ),
            severity: severity,
            code: code,
            source: "sourcekitd",
            message: "Cannot find 'foo' in scope"
        )
    }

    @Test func mapsRangesWithoutShifting() {
        let mapped = LSPDiagnosticMapping.workspaceDiagnostic(from: diagnostic(), fileURL: fileURL)
        #expect(mapped.startLine == 2)
        #expect(mapped.startColumn == 4)
        #expect(mapped.endLine == 2)
        #expect(mapped.endColumn == 12)
        #expect(mapped.fileURL == fileURL)
        #expect(mapped.message == "Cannot find 'foo' in scope")
        #expect(mapped.source == "sourcekitd")
    }

    @Test func mapsSeverities() {
        let expected: [(DiagnosticSeverity?, WorkspaceDiagnostic.Severity)] = [
            (.error, .error),
            (.warning, .warning),
            (.information, .information),
            (.hint, .hint),
            (nil, .error)
        ]
        for (input, output) in expected {
            #expect(LSPDiagnosticMapping.severity(from: input) == output)
        }
    }

    @Test func mapsCodes() {
        #expect(LSPDiagnosticMapping.code(from: .optionA(42)) == "42")
        #expect(LSPDiagnosticMapping.code(from: .optionB("unused")) == "unused")
        #expect(LSPDiagnosticMapping.code(from: nil) == nil)
    }

    @Test func mapsWholeLists() throws {
        let mapped = LSPDiagnosticMapping.workspaceDiagnostics(
            from: [diagnostic(), diagnostic(line: 9, severity: .warning)],
            fileURL: fileURL
        )
        try #require(mapped.count == 2)
        #expect(mapped[1].startLine == 9)
        #expect(mapped[1].severity == .warning)
    }

    @Test func parsesFileURIs() {
        let url = LSPDiagnosticMapping.fileURL(fromDocumentURI: "file:///tmp/project/a%20b.swift")
        #expect(url?.path == "/tmp/project/a b.swift")
        #expect(LSPDiagnosticMapping.fileURL(fromDocumentURI: "https://example.com") == nil)
    }
}
