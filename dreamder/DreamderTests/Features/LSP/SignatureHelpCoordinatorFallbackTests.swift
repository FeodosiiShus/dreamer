import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct SignatureHelpCoordinatorFallbackTests {
    private static let source = "greet(first, second) tail\nnext line\n"
    private static let insideCall = 12
    private static let afterCall = 20
    private static let escapeKey: UInt16 = 53

    private func shownPopup(of coordinator: SignatureHelpCoordinator) throws -> SignatureHelpPopup {
        let child = try #require(Mirror(reflecting: coordinator).children.first { $0.label == "popup" })
        return try #require(child.value as? SignatureHelpPopup)
    }

    private func escapeEvent(windowNumber: Int) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: windowNumber,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: Self.escapeKey
            )
        )
    }

    @Test
    func theKeyHandlerOfAReleasedCoordinatorLeavesTheKeyAlone() throws {
        try withTempDir { directory in
            let fixture = try HostedSourceEditorFixture.make(in: directory, contents: "greet")
            var coordinator: SignatureHelpCoordinator? = SignatureHelpCoordinator(
                editorInstance: fixture.editorInstance,
                codeFile: fixture.document,
                clientProvider: { nil }
            )
            let popup = try shownPopup(of: #require(coordinator))
            let event = try escapeEvent(windowNumber: 0)

            coordinator = nil

            #expect(popup.keyHandler?(event) == false)
        }
    }

    @Test
    func escapeAfterThePopupWasClosedStillResolvesWithoutSignatures() async throws {
        try await withTempDir { directory in
            let harness = try await SignatureHelpEditorHarness.open(in: directory, contents: Self.source)
            defer { harness.close() }
            harness.connection.answer(with: SignatureHelpFixtures.twoOverloads())
            harness.moveCaret(to: Self.insideCall)
            await harness.coordinator.showParameterInfo()
            let popup = try shownPopup(of: harness.coordinator)
            harness.coordinator.controllerDidDisappear(controller: harness.controller)
            #expect(harness.coordinator.shownPresentation == nil)
            harness.hosted.window.makeFirstResponder(harness.textView)

            let consumed = popup.keyHandler?(try harness.keyEvent(Self.escapeKey))

            #expect(consumed == true)
            #expect(!harness.coordinator.isShowingParameterInfo)
        }
    }

    @Test
    func aMultiCharacterEditWithoutASelectionFallsBackToTheTypedCaret() async throws {
        try await withTempDir { directory in
            let harness = try await SignatureHelpEditorHarness.open(in: directory, contents: Self.source)
            defer { harness.close() }
            harness.connection.answer(with: SignatureHelpFixtures.twoOverloads())
            harness.moveCaret(to: Self.insideCall)
            await harness.coordinator.showParameterInfo()
            #expect(harness.coordinator.isShowingParameterInfo)
            harness.textView.selectionManager.setSelectedRanges([])

            harness.coordinator.textView(
                harness.textView,
                didReplaceContentsIn: NSRange(location: Self.afterCall, length: 0),
                with: "ab"
            )

            #expect(!harness.coordinator.isShowingParameterInfo)
            #expect(harness.childPanels.isEmpty)
        }
    }

    @Test
    func aResponseArrivingAfterTheSelectionWasClearedAnchorsAtTheRequestedCaret() async throws {
        try await withTempDir { directory in
            let harness = try await SignatureHelpEditorHarness.open(in: directory, contents: Self.source)
            defer { harness.close() }
            harness.connection.answer(with: SignatureHelpFixtures.twoOverloads())
            harness.connection.hold()
            harness.moveCaret(to: Self.insideCall)
            let coordinator = harness.coordinator
            let request = Task { @MainActor in await coordinator.showParameterInfo() }
            try await eventually { harness.connection.receivedParams.count == 1 }
            harness.textView.selectionManager.setSelectedRanges([])

            harness.connection.release()
            await request.value

            #expect(harness.coordinator.isShowingParameterInfo)
            let panel = try #require(harness.childPanels.first)
            let anchor = try harness.caretAnchor(Self.insideCall)
            let expected = SignatureHelpPlacement.frame(
                size: panel.frame.size,
                anchor: anchor,
                visibleFrame: SignatureHelpPopup.screenVisibleFrame(containing: anchor)
            )
            #expect(abs(panel.frame.minX - expected.minX) < 1)
        }
    }
}
