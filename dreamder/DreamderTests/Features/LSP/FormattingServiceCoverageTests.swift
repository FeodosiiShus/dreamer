import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite("FormattingServiceCoverage", .uiGate)
struct FormattingServiceCoverageTests {
    @Test
    func aFileWithoutALanguageServerCannotBeFormattedAndNothingIsSent() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingHarness.make(in: directory)
            defer { harness.close() }
            let service = FormattingService(lspService: { nil }, fileExists: { _ in false }, workspaceRoot: { _ in nil })

            #expect(!service.canFormatDocument(harness.document))
            #expect(await service.formatDocument(harness.document) == .unavailable)
            #expect(harness.connection.formattingParams.isEmpty)
            #expect(harness.text == "let  x = 1\n")
        }
    }

    @Test
    func editsThatCannotReachTheOpenDocumentCountAsAFailedFormat() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingHarness.make(in: directory)
            let storage = harness.document.content
            defer {
                harness.document.content = storage
                harness.close()
            }
            try harness.scriptFormatting(.textDocumentFormatting, edits: [harness.spacesEdit()])
            harness.document.content = nil

            let outcome = await harness.formattingService().formatDocument(harness.document)

            #expect(outcome == .failed)
            #expect(harness.text == "let  x = 1\n")
        }
    }
}
