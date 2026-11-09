import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageServerProtocol
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class SignatureHelpCompletionFlag {
    var value = true
}

@MainActor
@Suite(.uiGate)
struct SignatureHelpCoordinatorTests {
    private typealias Fixtures = SignatureHelpFixtures
    private typealias Harness = SignatureHelpEditorHarness

    private static let source = "greet(first, second) tail\nnext line\n"
    private static let insideCall = 12
    private static let afterCall = 20
    private static let escapeKey: UInt16 = 53
    private static let upKey: UInt16 = 126
    private static let downKey: UInt16 = 125

    private func open(
        _ directory: URL,
        contents: String = SignatureHelpCoordinatorTests.source,
        provider: SignatureHelpOptions? = SignatureHelpOptions(),
        answer: SignatureHelp? = SignatureHelpFixtures.twoOverloads(),
        visibleFrame: SignatureHelpPopup.VisibleFrameProvider? = nil,
        useServiceLookup: Bool = false
    ) async throws -> Harness {
        let harness = try await Harness.open(
            in: directory,
            contents: contents,
            provider: provider,
            visibleFrame: visibleFrame,
            useServiceLookup: useServiceLookup
        )
        harness.connection.answer(with: answer)
        return harness
    }

    private func showInsideTheCall(_ harness: Harness, at offset: Int = SignatureHelpCoordinatorTests.insideCall) async {
        harness.moveCaret(to: offset)
        await harness.coordinator.showParameterInfo()
    }

    @Test
    func showParameterInfoSendsAnInvokedRequestAndShowsThePopupAboveTheCaret() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory)
            defer { harness.close() }

            await showInsideTheCall(harness)

            let params = try #require(harness.connection.receivedParams.first)
            #expect(harness.connection.receivedParams.count == 1)
            #expect(params.context == .invoked(activeSignatureHelp: nil))
            #expect(params.position == Position(line: 0, character: Self.insideCall))
            #expect(params.textDocument.uri == harness.fixture.document.languageServerURI)
            #expect(harness.coordinator.isShowingParameterInfo)
            #expect(harness.coordinator.shownPresentation?.rows.count == 2)
            let panel = try #require(harness.childPanels.first)
            let anchor = try harness.caretAnchor(Self.insideCall)
            #expect(abs(panel.frame.minY - (anchor.maxY + SignatureHelpPlacement.gap)) < 1)
            #expect(abs(panel.frame.minX - anchor.minX) < 1)
            #expect(harness.coordinator.shownPanelFrame == panel.frame)
        }
    }

    @Test
    func invokingWhileOpenRetriggersWithTheActiveSignatureHelp() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory)
            defer { harness.close() }

            await showInsideTheCall(harness)
            await harness.coordinator.showParameterInfo()

            let second = try #require(harness.connection.receivedParams.last)
            #expect(harness.connection.receivedParams.count == 2)
            #expect(second.context.triggerKind == .invoked)
            #expect(second.context.isRetrigger)
            #expect(second.context.activeSignatureHelp == Fixtures.twoOverloads())
            #expect(harness.childPanels.count == 1)
        }
    }

    @Test
    func popupFlipsBelowTheCaretWhenTheScreenHasNoRoomAbove() async throws {
        try await withTempDir { directory in
            let harness = try await open(
                directory,
                visibleFrame: { anchor in NSRect(x: -100_000, y: anchor.minY - 400, width: 200_000, height: 400 + anchor.height + 40) }
            )
            defer { harness.close() }

            await showInsideTheCall(harness)

            let panel = try #require(harness.childPanels.first)
            let anchor = try harness.caretAnchor(Self.insideCall)
            #expect(panel.frame.maxY <= anchor.minY)
        }
    }

    @Test
    func typingAnOpenParenAsksForSignatureHelpAndShowsThePopup() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory, contents: "greet")
            defer { harness.close() }
            harness.moveCaret(to: 5)

            harness.type("(")
            try await eventually { harness.coordinator.isShowingParameterInfo }

            let params = try #require(harness.connection.receivedParams.first)
            #expect(params.context == .typed("(", activeSignatureHelp: nil))
            #expect(params.position == Position(line: 0, character: 6))
            #expect(harness.childPanels.count == 1)
        }
    }

    @Test
    func typingRefreshesTheActiveParameterAndAClosingParenCloses() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory, contents: "greet")
            defer { harness.close() }
            harness.moveCaret(to: 5)
            harness.type("(")
            try await eventually { harness.coordinator.isShowingParameterInfo }

            harness.type("x")
            try await eventually { harness.connection.receivedParams.count == 2 }
            let change = harness.connection.receivedParams[1]
            #expect(change.context.triggerKind == .contentChange)
            #expect(change.context.isRetrigger)
            #expect(change.context.activeSignatureHelp == Fixtures.twoOverloads())
            #expect(change.position == Position(line: 0, character: 7))
            #expect(harness.coordinator.isShowingParameterInfo)

            harness.type(",")
            try await eventually { harness.connection.receivedParams.count == 3 }
            let comma = harness.connection.receivedParams[2]
            #expect(comma.context == .typed(",", activeSignatureHelp: Fixtures.twoOverloads()))
            #expect(comma.position == Position(line: 0, character: 8))

            harness.type(")")
            #expect(!harness.coordinator.isShowingParameterInfo)
            #expect(harness.childPanels.isEmpty)
            #expect(try await harness.requests().count == 3)
        }
    }

    @Test
    func aTriggerCharacterTypedBeforeTheServerAnsweredCancelsTheEarlierRequest() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory, contents: "greet")
            defer { harness.close() }
            harness.moveCaret(to: 5)

            harness.type("(")
            harness.type(",")
            try await eventually { harness.coordinator.isShowingParameterInfo }

            let params = try await harness.requests()
            #expect(params.map(\.context.triggerCharacter) == [","])
            #expect(params.map(\.context.isRetrigger) == [false])
        }
    }

    @Test
    func typingOtherCharactersWhileClosedOrPastingNeverAsksTheServer() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory, contents: "greet")
            defer { harness.close() }
            harness.moveCaret(to: 5)

            harness.type("x")
            harness.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "abc")
            harness.textView.replaceCharacters(in: NSRange(location: 0, length: 3), with: "")

            #expect(try await harness.requests().isEmpty)
            #expect(!harness.coordinator.isShowingParameterInfo)
        }
    }

    @Test
    func commaTypedInsideAnArgumentListOpensWithTheFallbackTriggers() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory, contents: "greet(first")
            defer { harness.close() }
            harness.moveCaret(to: 11)

            harness.type(",")
            try await eventually { harness.coordinator.isShowingParameterInfo }

            let params = try #require(harness.connection.receivedParams.first)
            #expect(params.context == .typed(",", activeSignatureHelp: nil))
            #expect(params.position == Position(line: 0, character: 12))
        }
    }

    @Test
    func triggerAndRetriggerCharactersComeFromTheServerCapabilities() async throws {
        try await withTempDir { directory in
            let harness = try await open(
                directory,
                contents: "greet",
                provider: SignatureHelpOptions(triggerCharacters: ["<"], retriggerCharacters: [";"])
            )
            defer { harness.close() }
            harness.moveCaret(to: 5)

            harness.type("(")
            #expect(try await harness.requests().isEmpty)
            harness.type("<")
            try await eventually { harness.coordinator.isShowingParameterInfo }
            #expect(harness.connection.receivedParams.map(\.context.triggerCharacter) == ["<"])

            harness.type(";")
            try await eventually { harness.connection.receivedParams.count == 2 }
            let retrigger = harness.connection.receivedParams[1]
            #expect(retrigger.context.triggerCharacter == ";")
            #expect(retrigger.context.isRetrigger)
        }
    }

    @Test
    func dynamicallyRegisteredTriggerCharactersArePickedUp() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory, contents: "greet", provider: nil)
            defer { harness.close() }
            harness.server.dynamicCapabilities.register([
                Registration(
                    id: "signature",
                    method: "textDocument/signatureHelp",
                    registerOptions: ["triggerCharacters": ["!"]]
                )
            ])
            harness.moveCaret(to: 5)

            harness.type("(")
            #expect(try await harness.requests().isEmpty)
            harness.type("!")
            try await eventually { harness.coordinator.isShowingParameterInfo }

            #expect(harness.connection.receivedParams.map(\.context.triggerCharacter) == ["!"])
        }
    }

    @Test
    func serverWithoutSignatureHelpIsNeverAsked() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory, provider: nil)
            defer { harness.close() }
            harness.moveCaret(to: Self.insideCall)

            await harness.coordinator.showParameterInfo()
            harness.type("(")
            harness.type(",")

            #expect(try await harness.requests().isEmpty)
            #expect(!harness.coordinator.isShowingParameterInfo)
            #expect(harness.childPanels.isEmpty)
        }
    }

    @Test
    func caretLeavingTheCallClosesThePopupWithoutAskingTheServer() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory)
            defer { harness.close() }
            await showInsideTheCall(harness)

            harness.moveCaret(to: Self.afterCall)

            #expect(!harness.coordinator.isShowingParameterInfo)
            #expect(harness.childPanels.isEmpty)
            #expect(try await harness.requests().count == 1)
        }
    }

    @Test
    func caretMovingInsideTheCallRefreshesTheActiveParameter() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory)
            defer { harness.close() }
            await showInsideTheCall(harness)

            harness.coordinator.textViewDidChangeSelection(
                controller: harness.controller,
                newPositions: [CursorPosition(range: NSRange(location: Self.insideCall, length: 0))]
            )
            #expect(try await harness.requests().count == 1)

            harness.moveCaret(to: 14)
            try await eventually { harness.connection.receivedParams.count == 2 }

            let refresh = harness.connection.receivedParams[1]
            #expect(refresh.context.triggerKind == .contentChange)
            #expect(refresh.context.isRetrigger)
            #expect(refresh.context.activeSignatureHelp == Fixtures.twoOverloads())
            #expect(refresh.position == Position(line: 0, character: 14))
            #expect(harness.coordinator.isShowingParameterInfo)
        }
    }

    @Test
    func popupWithoutAKnownCallRegionStaysOpenAndRefreshesWhenTheCaretMoves() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory, contents: "greet")
            defer { harness.close() }
            await showInsideTheCall(harness, at: 5)
            #expect(harness.coordinator.isShowingParameterInfo)

            harness.moveCaret(to: 2)
            try await eventually { harness.connection.receivedParams.count == 2 }

            #expect(harness.coordinator.isShowingParameterInfo)
            harness.type("a")
            try await eventually { harness.connection.receivedParams.count == 3 }
            #expect(harness.coordinator.isShowingParameterInfo)
        }
    }

    @Test
    func emptyAnswersCloseThePopup() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory)
            defer { harness.close() }
            let answers: [SignatureHelp?] = [nil, SignatureHelp(signatures: [])]

            for (index, answer) in answers.enumerated() {
                harness.connection.answer(with: Fixtures.twoOverloads())
                await showInsideTheCall(harness, at: 12 + index)
                #expect(harness.coordinator.isShowingParameterInfo)

                harness.connection.answer(with: answer)
                harness.moveCaret(to: 14 + index)
                try await eventually { !harness.coordinator.isShowingParameterInfo }

                #expect(harness.childPanels.isEmpty)
            }
        }
    }

    @Test
    func failedRequestsNeverShowOrKeepThePopup() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory)
            defer { harness.close() }
            harness.connection.failRequests(true)

            await showInsideTheCall(harness)
            #expect(!harness.coordinator.isShowingParameterInfo)
            #expect(harness.childPanels.isEmpty)

            harness.connection.failRequests(false)
            await showInsideTheCall(harness)
            #expect(harness.coordinator.isShowingParameterInfo)
            harness.connection.failRequests(true)
            harness.moveCaret(to: 14)
            try await eventually { !harness.coordinator.isShowingParameterInfo }
        }
    }

    @Test
    func olderResponsesAreDroppedWhenANewerRequestWasStarted() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory, contents: "greet")
            defer { harness.close() }
            harness.connection.hold()
            harness.connection.enqueue([Fixtures.oneOverload(), Fixtures.twoOverloads()])
            harness.moveCaret(to: 5)

            harness.type("(")
            try await eventually { harness.connection.receivedParams.count == 1 }
            harness.type(",")
            try await eventually { harness.connection.receivedParams.count == 2 }
            harness.connection.release()

            try await eventually { harness.coordinator.shownPresentation?.rows.count == 2 }
            try await Task.sleep(for: .milliseconds(100))
            #expect(harness.coordinator.shownPresentation?.rows.count == 2)
        }
    }

    @Test
    func responsesArrivingAfterTheEditorWentAwayAreIgnored() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory, contents: "greet")
            defer { harness.close() }
            harness.connection.hold()
            harness.moveCaret(to: 5)
            harness.type("(")
            try await eventually { harness.connection.receivedParams.count == 1 }

            harness.coordinator.controllerDidDisappear(controller: harness.controller)
            harness.connection.release()

            try await Task.sleep(for: .milliseconds(100))
            #expect(!harness.coordinator.isShowingParameterInfo)
            #expect(harness.childPanels.isEmpty)
        }
    }

    @Test
    func escapeClosesThePopupOnlyForTheFocusedEditorWindow() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory)
            defer { harness.close() }
            let other = HostedViewFixture.host { Color.clear }
            defer { other.close() }
            await showInsideTheCall(harness)

            NSApp.sendEvent(try harness.keyEvent(Self.escapeKey, in: other.window))
            #expect(harness.coordinator.isShowingParameterInfo)

            harness.hosted.window.makeFirstResponder(nil)
            NSApp.sendEvent(try harness.keyEvent(Self.escapeKey))
            #expect(harness.coordinator.isShowingParameterInfo)

            harness.hosted.window.makeFirstResponder(harness.textView)
            NSApp.sendEvent(try harness.keyEvent(Self.escapeKey))
            #expect(!harness.coordinator.isShowingParameterInfo)
            #expect(harness.childPanels.isEmpty)
        }
    }

    @Test
    func defaultProvidersPlaceThePopupOnTheScreenAndLetEscapeDismissIt() async throws {
        try await withTempDir { directory in
            let harness = try await Harness.open(
                in: directory,
                contents: Self.source,
                useDefaultProviders: true
            )
            defer { harness.close() }
            harness.connection.answer(with: Fixtures.twoOverloads())
            await showInsideTheCall(harness)
            #expect(harness.coordinator.isShowingParameterInfo)
            #expect(harness.childPanels.count == 1)

            harness.hosted.window.makeFirstResponder(harness.textView)
            NSApp.sendEvent(try harness.keyEvent(Self.escapeKey))
            #expect(!harness.coordinator.isShowingParameterInfo)
        }
    }

    @Test
    func arrowKeysCycleThroughTheSignaturesWithoutMovingTheCaret() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory)
            defer { harness.close() }
            await showInsideTheCall(harness)
            #expect(harness.coordinator.shownPresentation?.activeIndex == 0)

            NSApp.sendEvent(try harness.keyEvent(Self.downKey, modifiers: [.function, .numericPad]))
            #expect(harness.coordinator.shownPresentation?.activeIndex == 1)
            NSApp.sendEvent(try harness.keyEvent(Self.downKey))
            #expect(harness.coordinator.shownPresentation?.activeIndex == 0)
            NSApp.sendEvent(try harness.keyEvent(Self.upKey))
            #expect(harness.coordinator.shownPresentation?.activeIndex == 1)
            NSApp.sendEvent(try harness.keyEvent(Self.upKey, modifiers: [.option]))
            #expect(harness.coordinator.shownPresentation?.activeIndex == 0)

            #expect(harness.caret == Self.insideCall)
            #expect(harness.coordinator.isShowingParameterInfo)
        }
    }

    @Test
    func retriggerAfterCyclingCarriesTheSelectedSignature() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory)
            defer { harness.close() }
            await showInsideTheCall(harness)
            NSApp.sendEvent(try harness.keyEvent(Self.downKey))

            await harness.coordinator.showParameterInfo()

            let retrigger = try #require(harness.connection.receivedParams.last)
            #expect(retrigger.context.activeSignatureHelp?.activeSignature == 1)
        }
    }

    @Test
    func popupLeavesKeysToAVisibleCompletionWindow() async throws {
        try await withTempDir { directory in
            let completionVisible = SignatureHelpCompletionFlag()
            let harness = try await Harness.open(
                in: directory,
                contents: Self.source,
                isCompletionWindowVisible: { completionVisible.value }
            )
            defer { harness.close() }
            harness.connection.answer(with: Fixtures.twoOverloads())
            await showInsideTheCall(harness)

            NSApp.sendEvent(try harness.keyEvent(Self.escapeKey))
            #expect(harness.coordinator.isShowingParameterInfo)
            #expect(harness.coordinator.shownPresentation?.activeIndex == 0)

            completionVisible.value = false
            NSApp.sendEvent(try harness.keyEvent(Self.downKey))
            #expect(harness.coordinator.shownPresentation?.activeIndex == 1)
            NSApp.sendEvent(try harness.keyEvent(Self.escapeKey))
            #expect(!harness.coordinator.isShowingParameterInfo)
        }
    }

    @Test
    func liveCompletionWindowCheckIsFalseWithoutACompletionWindow() {
        #expect(!SignatureHelpCoordinator.isSuggestionWindowVisible())
    }

    @Test
    func keysThePopupDoesNotHandleReachTheEditor() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory, answer: Fixtures.oneOverload())
            defer { harness.close() }
            await showInsideTheCall(harness)

            NSApp.sendEvent(try harness.keyEvent(0))
            #expect(harness.coordinator.shownPresentation?.activeIndex == 0)
            NSApp.sendEvent(try harness.keyEvent(Self.downKey))

            #expect(harness.coordinator.shownPresentation?.activeIndex ?? 0 == 0)
        }
    }

    @Test
    func editsBeforeTheCallShiftTheRegionAndEditsOfTheParenCloseThePopup() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory)
            defer { harness.close() }
            await showInsideTheCall(harness)

            harness.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "xx")
            #expect(harness.coordinator.isShowingParameterInfo)
            try await eventually { harness.connection.receivedParams.count == 2 }
            #expect(harness.coordinator.isShowingParameterInfo)

            let paren = (harness.textView.string as NSString).range(of: "(")
            harness.textView.replaceCharacters(in: paren, with: "x")
            #expect(!harness.coordinator.isShowingParameterInfo)
        }
    }

    @Test
    func lifecycleCallbacksCloseThePopupAndDestroyDetachesTheController() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory)
            defer { harness.close() }
            await showInsideTheCall(harness)

            harness.coordinator.controllerDidDisappear(controller: harness.controller)
            #expect(!harness.coordinator.isShowingParameterInfo)
            #expect(harness.coordinator.shownPanelFrame == nil)
            #expect(harness.coordinator.shownPresentation == nil)

            await showInsideTheCall(harness)
            #expect(harness.coordinator.isShowingParameterInfo)
            harness.coordinator.destroy()
            #expect(!harness.coordinator.isShowingParameterInfo)
            #expect(harness.childPanels.isEmpty)

            await harness.coordinator.showParameterInfo()
            #expect(!harness.coordinator.isShowingParameterInfo)
            #expect(harness.connection.receivedParams.count == 2)
        }
    }

    @Test
    func theCoordinatorRegistersItselfInTheEditorFeatureHub() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory)
            defer { harness.close() }

            #expect(EditorFeatureHubs.hub(for: harness.fixture.editorInstance).signatureHelp === harness.coordinator)
        }
    }

    @Test
    func defaultClientComesFromTheLanguageServiceAndNeedsAFileUrl() async throws {
        try await withTempDir { directory in
            let service = LSPService.shared
            let harness = try await open(directory, useServiceLookup: true)
            defer { harness.close() }
            let key = LSPService.ClientKey(.swift, directory.path() + "/")
            harness.moveCaret(to: Self.insideCall)

            await harness.coordinator.showParameterInfo()
            #expect(harness.connection.receivedParams.isEmpty)

            service.languageClients[key] = harness.server
            defer { service.languageClients[key] = nil }
            await harness.coordinator.showParameterInfo()
            #expect(harness.connection.receivedParams.count == 1)
            #expect(harness.coordinator.isShowingParameterInfo)

            let url = harness.fixture.document.fileURL
            harness.fixture.document.fileURL = nil
            await harness.coordinator.showParameterInfo()
            harness.fixture.document.fileURL = url
            #expect(harness.connection.receivedParams.count == 1)
        }
    }

    @Test
    func releasingTheCoordinatorClosesItsPopup() async throws {
        try withTempDir { directory in
            let fixture = try HostedSourceEditorFixture.make(in: directory, contents: "greet")
            var coordinator: SignatureHelpCoordinator? = SignatureHelpCoordinator(
                editorInstance: fixture.editorInstance,
                codeFile: fixture.document,
                clientProvider: { nil }
            )
            weak let weakCoordinator = coordinator

            coordinator = nil

            #expect(weakCoordinator == nil)
        }
    }
}
