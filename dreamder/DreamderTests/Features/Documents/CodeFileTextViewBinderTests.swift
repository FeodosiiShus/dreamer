import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct CodeFileTextViewBinderTests {
    private func makeController(for document: CodeFileDocument) throws -> TextViewController {
        let theme = try #require(ThemeModel.shared.selectedTheme ?? ThemeModel.shared.themes.first)
        return TextViewController(
            string: "text",
            language: .swift,
            configuration: SourceEditorConfiguration(
                appearance: .init(
                    theme: theme.editor.editorTheme,
                    font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    wrapLines: false
                )
            ),
            cursorPositions: [],
            highlightProviders: [],
            coordinators: [document.textViewBinder]
        )
    }

    private func close(_ controller: inout TextViewController?) async throws {
        weak let closed = controller
        controller = nil
        try await eventually(timeout: .seconds(20)) { closed == nil }
    }

    @Test
    func theLatestControllerIsTheBoundOne() throws {
        let document = CodeFileDocument()
        let first = try makeController(for: document)
        #expect(document.attachedController === first)

        let second = try makeController(for: document)

        #expect(document.attachedController === second)
        #expect(document.attachedTextView === second.textView)
        withExtendedLifetime(first) {}
    }

    @Test
    func closingTheFirstSplitKeepsTheSecondSplitBound() async throws {
        let document = CodeFileDocument()
        var first: TextViewController? = try makeController(for: document)
        let second = try makeController(for: document)

        try await close(&first)

        #expect(document.attachedController === second)
        #expect(document.attachedTextView === second.textView)
    }

    @Test
    func closingTheLatestSplitBindsTheSplitThatIsStillOpen() async throws {
        let document = CodeFileDocument()
        let first = try makeController(for: document)
        var second: TextViewController? = try makeController(for: document)
        #expect(document.attachedController === second)

        try await close(&second)

        #expect(document.attachedController === first)
        #expect(document.attachedTextView === first.textView)
    }

    @Test
    func closingTheLastSplitDetachesTheDocument() async throws {
        let document = CodeFileDocument()
        var only: TextViewController? = try makeController(for: document)
        #expect(document.attachedTextView === only?.textView)

        try await close(&only)

        #expect(document.attachedController == nil)
        #expect(document.attachedTextView == nil)
    }

    @Test
    func closingSplitsOneByOneAlwaysLeavesTheSurvivorBound() async throws {
        let document = CodeFileDocument()
        let oldest = try makeController(for: document)
        var middle: TextViewController? = try makeController(for: document)
        var newest: TextViewController? = try makeController(for: document)

        try await close(&middle)
        #expect(document.attachedController === newest)

        try await close(&newest)
        #expect(document.attachedController === oldest)
    }

    @Test
    func splitsOfOtherDocumentsAreNeverRebound() async throws {
        let document = CodeFileDocument()
        let other = CodeFileDocument()
        let otherController = try makeController(for: other)
        var controller: TextViewController? = try makeController(for: document)

        try await close(&controller)

        #expect(document.attachedController == nil)
        #expect(other.attachedController === otherController)
    }
}
