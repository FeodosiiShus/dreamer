import Foundation
import JSONRPC
import LanguageServerProtocol
import Testing
@testable import Dreamder

private struct RenameModelsFailure: Error, LocalizedError {
    var errorDescription: String? { "boom" }
}

@MainActor
@Suite(.uiGate)
struct RenameModelsTests {
    private let document = "hello world\nsecond line\n"

    private func range(_ line: Int, _ start: Int, _ end: Int) -> LSPRange {
        SyncTestServer.range(line, start, end)
    }

    private func target(_ response: PrepareRenameResponse, symbol: String = "word") -> RenameTargetResolution {
        RenameTargetMapping.resolve(response, documentText: document, symbol: symbol)
    }

    @Test
    func lspRenameTestPrepareRenameReturnsRangeAndPlaceholder() {
        let response: PrepareRenameResponse = .optionB(
            RangeWithPlaceholder(range: range(0, 0, 5), placeholder: "hello")
        )

        #expect(target(response) == .target(RenameTarget(name: "hello", range: range(0, 0, 5))))
    }

    @Test
    func theServerPlaceholderWinsOverTheTextInTheRange() {
        let response: PrepareRenameResponse = .optionB(
            RangeWithPlaceholder(range: range(0, 0, 5), placeholder: "greeting")
        )

        #expect(target(response) == .target(RenameTarget(name: "greeting", range: range(0, 0, 5))))
    }

    @Test
    func anEmptyPlaceholderFallsBackToTheTextInTheRange() {
        let response: PrepareRenameResponse = .optionB(
            RangeWithPlaceholder(range: range(1, 0, 6), placeholder: "")
        )

        #expect(target(response) == .target(RenameTarget(name: "second", range: range(1, 0, 6))))
    }

    @Test
    func lspRenameTestPrepareRenameWithRangeOnlyUsesDocumentText() {
        let response: PrepareRenameResponse = .optionA(range(0, 6, 11))

        #expect(target(response) == .target(RenameTarget(name: "world", range: range(0, 6, 11))))
    }

    @Test
    func aRangeOutsideTheDocumentFallsBackToTheCaretWord() {
        let response: PrepareRenameResponse = .optionA(range(9, 0, 3))

        #expect(target(response) == .target(RenameTarget(name: "word", range: range(9, 0, 3))))
    }

    @Test
    func aRangeOutsideTheDocumentWithoutACaretWordIsNotRenameable() {
        let response: PrepareRenameResponse = .optionA(range(9, 0, 3))

        #expect(target(response, symbol: "") == .notRenameable)
    }

    @Test
    func lspRenameTestPrepareRenameWithDefaultBehaviorFallsBackToWordRange() {
        let response: PrepareRenameResponse = .optionC(PrepareRenameDefaultBehavior(defaultBehavior: true))

        #expect(target(response) == .target(RenameTarget(name: "word", range: nil)))
        #expect(target(response, symbol: "") == .notRenameable)
    }

    @Test
    func aDisabledDefaultBehaviorIsNotRenameable() {
        let response: PrepareRenameResponse = .optionC(PrepareRenameDefaultBehavior(defaultBehavior: false))

        #expect(target(response) == .notRenameable)
    }

    @Test
    func aNullPrepareResponseIsNotRenameable() {
        #expect(target(nil) == .notRenameable)
    }

    @Test
    func theFallbackUsesTheWordUnderTheCaret() {
        #expect(RenameTargetMapping.fallback(symbol: "hello") == .target(RenameTarget(name: "hello", range: nil)))
        #expect(RenameTargetMapping.fallback(symbol: "") == .notRenameable)
    }

    @Test
    func validationFollowsTheRenameDialogRules() {
        #expect(RenameNameValidator.validate("greetings", currentName: "hello") == .valid)
        #expect(RenameNameValidator.validate("  greetings\n", currentName: "hello") == .valid)
        #expect(RenameNameValidator.validate("hello", currentName: "hello") == .unchanged)
        #expect(RenameNameValidator.validate(" hello ", currentName: "hello") == .unchanged)
        #expect(RenameNameValidator.validate("", currentName: "hello") == .empty)
        #expect(RenameNameValidator.validate(" \n\t", currentName: "hello") == .empty)
        #expect(RenameNameValidator.validate("a b", currentName: "hello") == .invalidIdentifier("a b"))
        #expect(RenameNameValidator.validate("a\nb", currentName: "hello") == .invalidIdentifier("a\nb"))
        #expect(RenameNameValidator.normalized("  x  ") == "x")
    }

    @Test
    func onlyAValidNameCanBeConfirmedAndOnlyInvalidNamesShowAnError() {
        #expect(RenameNameValidation.valid.isConfirmable)
        #expect(!RenameNameValidation.unchanged.isConfirmable)
        #expect(!RenameNameValidation.empty.isConfirmable)
        #expect(!RenameNameValidation.invalidIdentifier("a b").isConfirmable)

        #expect(RenameNameValidation.valid.errorMessage == nil)
        #expect(RenameNameValidation.unchanged.errorMessage == nil)
        #expect(RenameNameValidation.empty.errorMessage == "The name must not be empty")
        #expect(RenameNameValidation.invalidIdentifier("a b").errorMessage == "'a b' is not a valid identifier")
    }

    @Test
    func messagesMatchTheIntelliJBundleTexts() {
        #expect(RenameMessages.prompt(for: "hello") == "Rename hello and its usages to:")
        #expect(RenameMessages.notRenameable == "Cannot rename this element")
        #expect(RenameMessages.nothingToRename == "Nothing to rename")
        #expect(RenameMessages.failure(reason: "locked") == "Cannot rename: locked")
        #expect(RenameMessages.failure(reason: nil) == "Cannot rename: The edit could not be applied")
    }

    @Test
    func failureMessagesUseTheServerErrorMessageWhenThereIsOne() {
        let rpc = AnyJSONRPCResponseError(code: -32803, message: "cannot rename here", data: nil)

        #expect(RenameMessages.failure(error: rpc) == "Cannot rename: cannot rename here")
        #expect(RenameMessages.failure(error: RenameModelsFailure()) == "Cannot rename: boom")
    }
}
