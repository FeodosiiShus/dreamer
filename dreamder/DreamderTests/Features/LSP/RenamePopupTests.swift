import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageClient
import LanguageServerProtocol
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct RenamePopupViewModelTests {
    private func model(_ name: String = "hello") -> RenamePopupViewModel {
        RenamePopupViewModel(target: RenameTarget(name: name, range: nil))
    }

    @Test
    func theFieldIsPrefilledWithTheCurrentNameAndThePromptNamesIt() {
        let model = model("greeting")

        #expect(model.name == "greeting")
        #expect(model.prompt == "Rename greeting and its usages to:")
        #expect(model.panelWidth == 380)
        #expect(model.preferredHeight == 104)
    }

    @Test
    func validationStatesFollowTheTypedName() {
        let model = model()

        #expect(model.validation == .unchanged)
        #expect(!model.isConfirmEnabled)
        #expect(model.errorMessage == nil)

        model.name = "greetings"
        #expect(model.validation == .valid)
        #expect(model.isConfirmEnabled)
        #expect(model.errorMessage == nil)

        model.name = "two words"
        #expect(model.validation == .invalidIdentifier("two words"))
        #expect(!model.isConfirmEnabled)
        #expect(model.errorMessage == "'two words' is not a valid identifier")

        model.name = "   "
        #expect(model.validation == .empty)
        #expect(!model.isConfirmEnabled)
        #expect(model.errorMessage == "The name must not be empty")
    }

    @Test
    func confirmingSendsTheTrimmedNameOnlyWhenItIsValid() {
        let model = model()
        var confirmed: [String] = []
        model.onConfirm = { confirmed.append($0) }

        model.confirm()
        model.name = "bad name"
        model.confirm()
        model.name = "  greetings \n"
        model.confirm()

        #expect(confirmed == ["greetings"])
    }

    @Test
    func cancellingCallsTheCancelHandler() {
        let model = model()
        var cancelled = 0
        model.onCancel = { cancelled += 1 }

        model.cancel()

        #expect(cancelled == 1)
    }

    @Test
    func returnConfirmsAndEscapeCancels() throws {
        let model = model()
        var confirmed: [String] = []
        var cancelled = 0
        model.onConfirm = { confirmed.append($0) }
        model.onCancel = { cancelled += 1 }
        model.name = "greetings"

        #expect(model.handle(event: try renameKeyEvent(36)))
        #expect(model.handle(event: try renameKeyEvent(76)))
        #expect(confirmed == ["greetings", "greetings"])
        #expect(model.handle(event: try renameKeyEvent(53)))
        #expect(cancelled == 1)

        model.name = "bad name"
        #expect(model.handle(event: try renameKeyEvent(36)))
        #expect(confirmed.count == 2)
    }

    @Test
    func otherKeysAndModifiedKeysAreNotHandled() throws {
        let model = model()
        var confirmed = 0
        var cancelled = 0
        model.onConfirm = { _ in confirmed += 1 }
        model.onCancel = { cancelled += 1 }
        model.name = "greetings"

        #expect(model.handle(event: try renameKeyEvent(0)) == false)
        #expect(model.handle(event: try renameKeyEvent(36, flags: .command)) == false)
        #expect(model.handle(event: try renameKeyEvent(53, flags: .option)) == false)
        #expect(confirmed == 0)
        #expect(cancelled == 0)
    }
}

@MainActor
@Suite(.uiGate)
struct RenamePopupViewTests {
    private func model(_ name: String = "hello") -> RenamePopupViewModel {
        RenamePopupViewModel(target: RenameTarget(name: name, range: nil))
    }

    @Test
    func theFieldShowsTheCurrentNameAndTheViewRenders() async throws {
        let model = model("greeting")
        let hosted = HostedViewFixture.host(size: NSSize(width: 380, height: 104)) {
            RenamePopupView(model: model)
        }
        defer { hosted.close() }

        try await hosted.settle()

        #expect(hosted.views(of: NSTextField.self).contains { $0.stringValue == "greeting" })
        #expect(hosted.renders())
    }

    @Test
    func everyValidationStateRendersAndTheErrorLooksDifferent() async throws {
        let model = model()
        let hosted = HostedViewFixture.host(size: NSSize(width: 380, height: 104)) {
            RenamePopupView(model: model)
        }
        defer { hosted.close() }

        try await hosted.settle()
        let unchanged = hosted.snapshot()
        #expect(hosted.renders())

        model.name = "greetings"
        try await hosted.settle(.milliseconds(150))
        let valid = hosted.snapshot()
        #expect(hosted.renders())

        model.name = "two words"
        try await hosted.settle(.milliseconds(150))
        let invalid = hosted.snapshot()
        #expect(hosted.renders())

        model.name = ""
        try await hosted.settle(.milliseconds(150))
        let empty = hosted.snapshot()
        #expect(hosted.renders())

        #expect(HostedView.pixelsDiffer(valid, invalid))
        #expect(HostedView.pixelsDiffer(unchanged, valid))
        #expect(HostedView.pixelsDiffer(invalid, empty))
    }
}
