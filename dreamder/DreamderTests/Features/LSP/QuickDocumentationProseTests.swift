import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct QuickDocumentationProseTests {
    private struct ParseFailure: Error {}

    @Test
    func inlineMarkdownIsParsedWithItsWhitespaceKept() {
        let prose = QuickDocumentationView.prose("Sends  a **message**")

        #expect(String(prose.characters) == "Sends  a message")
        #expect(prose.runs.contains { $0.inlinePresentationIntent == .stronglyEmphasized })
    }

    @Test
    func aParserFailureFallsBackToTheLiteralText() {
        let prose = QuickDocumentationView.prose("Sends **message**") { _, _ in throw ParseFailure() }

        #expect(String(prose.characters) == "Sends **message**")
        #expect(prose.runs.allSatisfy { $0.inlinePresentationIntent == nil })
    }
}
