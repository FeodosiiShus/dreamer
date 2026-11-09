import AppKit
import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite("OptimizeImports", .uiGate)
struct FormattingOptimizeImportsTests {
    typealias Response = [TwoTypeOption<LSPCommand, CodeAction>]

    private static let unsorted = "import B\nimport A\nlet x = 1\n"
    private static let sorted = "import A\nimport B\nlet x = 1\n"

    private func make(
        in directory: URL,
        codeActions: Bool = true
    ) async throws -> FormattingHarness {
        try await FormattingHarness.make(
            in: directory,
            text: Self.unsorted,
            capabilities: FormattingHarness.capabilities(codeActions: codeActions)
        )
    }

    private func organizeAction(_ harness: FormattingHarness) -> CodeAction {
        let edit = WorkspaceEdit(
            changes: [harness.uri: [
                TextEdit(range: LSPRange(startPair: (0, 0), endPair: (2, 0)), newText: "import A\nimport B\n")
            ]],
            documentChanges: nil
        )
        return CodeAction(title: "Organize Imports", kind: CodeActionKind.SourceOrganizeImports, edit: edit)
    }

    private func optimizer(_ harness: FormattingHarness, recorder: FormattingRecorder = FormattingRecorder()) -> OptimizeImports {
        let service = harness.service
        return OptimizeImports(lspService: { service }, reportUnavailable: { recorder.unavailableCount += 1 })
    }

    @Test
    func requestsOrganizeImportsOverTheWholeDocumentAndAppliesTheFirstActionAsOneUndoStep() async throws {
        try await withTempDir { directory in
            let harness = try await make(in: directory)
            defer { harness.close() }
            let response: Response = [.optionB(organizeAction(harness))]
            try harness.connection.script(.textDocumentCodeAction, response)

            let outcome = await optimizer(harness).run(harness.document)

            #expect(outcome == .applied)
            #expect(harness.text == Self.sorted)
            #expect(harness.document.content?.string == Self.sorted)
            let params = try #require(harness.connection.codeActionParams.first)
            #expect(harness.connection.codeActionParams.count == 1)
            #expect(params.context.only == [CodeActionKind.SourceOrganizeImports])
            #expect(params.context.diagnostics.isEmpty)
            #expect(params.textDocument.uri == harness.uri)
            #expect(params.range == LSPRange(startPair: (0, 0), endPair: (3, 0)))

            harness.textView.undoManager?.undo()

            #expect(harness.text == Self.unsorted)
        }
    }

    @Test
    func aServerWithoutOrganizeImportsActionsLeavesTheTextAlone() async throws {
        try await withTempDir { directory in
            let harness = try await make(in: directory)
            defer { harness.close() }
            let response: Response = []
            try harness.connection.script(.textDocumentCodeAction, response)

            let outcome = await optimizer(harness).run(harness.document)

            #expect(outcome == .noActions)
            #expect(harness.text == Self.unsorted)
        }
    }

    @Test
    func aServerWithoutCodeActionsIsNotAsked() async throws {
        try await withTempDir { directory in
            let harness = try await make(in: directory, codeActions: false)
            defer { harness.close() }

            let outcome = await optimizer(harness).run(harness.document)

            #expect(outcome == .noActions)
            #expect(harness.connection.codeActionParams.isEmpty)
        }
    }

    @Test
    func anActionThatCannotBeAppliedFails() async throws {
        try await withTempDir { directory in
            let harness = try await make(in: directory)
            defer { harness.close() }
            let response: Response = [
                .optionB(CodeAction(title: "Organize Imports", kind: CodeActionKind.SourceOrganizeImports))
            ]
            try harness.connection.script(.textDocumentCodeAction, response)

            let outcome = await optimizer(harness).run(harness.document)

            #expect(outcome == .failed)
            #expect(harness.text == Self.unsorted)
        }
    }

    @Test
    func withoutAServerOrAFileTheActionBeeps() async throws {
        let recorder = FormattingRecorder()
        let optimizer = OptimizeImports(lspService: { nil }, reportUnavailable: { recorder.unavailableCount += 1 })

        let outcome = await optimizer.run(CodeFileDocument())

        #expect(outcome == .unavailable)
        #expect(recorder.unavailableCount == 1)
    }

    @Test
    func aFileWithoutAnOpenServerDocumentBeeps() async throws {
        try await withTempDir { directory in
            let url = directory.appending(path: "a.swift")
            try Self.unsorted.write(to: url, atomically: true, encoding: .utf8)
            let document = try CodeFileDocument(for: url, withContentsOf: url, ofType: "public.swift-source")
            let recorder = FormattingRecorder()
            let optimizer = OptimizeImports(lspService: { nil }, reportUnavailable: { recorder.unavailableCount += 1 })

            let outcome = await optimizer.run(document)

            #expect(outcome == .unavailable)
            #expect(recorder.unavailableCount == 1)
        }
    }

    @Test
    func theDefaultSeamsResolveTheSharedServiceAndBeep() {
        let optimizer = OptimizeImports()

        _ = optimizer.lspService()
        optimizer.reportUnavailable()
    }
}
