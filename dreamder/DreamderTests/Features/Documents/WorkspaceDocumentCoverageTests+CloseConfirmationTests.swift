import AppKit
import Foundation
import Testing
@testable import Dreamder

extension WorkspaceDocumentCoverageTests {
    @Test
    func editedFilesAreConfirmedOneAtATimeAndTheDelegateIsToldOnlyAfterTheLastAnswer() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, names: ["a.txt", "b.txt"])
            defer { harness.close() }
            let confirmation = CloseConfirmationDouble()
            harness.markEdited(using: confirmation)
            let recorder = DocumentCloseRecorder()
            let context = ContextToken()

            harness.workspace.shouldCloseWindowController(
                NSWindowController(),
                delegate: recorder,
                shouldClose: DocumentCloseRecorder.selector,
                contextInfo: context.raw
            )

            #expect(confirmation.askedNames == ["a.txt"])
            #expect(recorder.calls.isEmpty)

            confirmation.answerNext(.save)

            #expect(confirmation.askedNames == ["a.txt", "b.txt"])
            #expect(recorder.calls.isEmpty)

            confirmation.answerNext(.save)

            #expect(recorder.calls.map(\.shouldClose) == [true])
            #expect(recorder.calls.first?.document === harness.workspace)
            #expect(recorder.calls.first?.contextInfo == context.raw)
        }
    }

    @Test
    func discardingChangesLetsTheWorkspaceClose() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, names: ["a.txt"])
            defer { harness.close() }
            let confirmation = CloseConfirmationDouble(answering: .discard)
            harness.markEdited(using: confirmation)
            let recorder = DocumentCloseRecorder()

            harness.workspace.shouldCloseWindowController(
                NSWindowController(),
                delegate: recorder,
                shouldClose: DocumentCloseRecorder.selector,
                contextInfo: nil
            )

            #expect(recorder.calls.map(\.shouldClose) == [true])
            #expect(recorder.calls.first?.contextInfo == nil)
            #expect(harness.documents.allSatisfy { $0.isDocumentEdited })
        }
    }

    @Test
    func cancellingAConfirmationKeepsTheWorkspaceOpenWithItsEditsAndAsksNoFurther() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, names: ["a.txt", "b.txt"])
            defer { harness.close() }
            let confirmation = CloseConfirmationDouble()
            harness.markEdited(using: confirmation)
            let recorder = DocumentCloseRecorder()

            harness.workspace.shouldCloseWindowController(
                NSWindowController(),
                delegate: recorder,
                shouldClose: DocumentCloseRecorder.selector,
                contextInfo: nil
            )
            confirmation.answerNext(.cancel)

            #expect(confirmation.askedNames == ["a.txt"])
            #expect(confirmation.pendingCount == 0)
            #expect(recorder.calls.map(\.shouldClose) == [false])
            #expect(harness.documents.allSatisfy { $0.isDocumentEdited })
            #expect(harness.documents.allSatisfy { $0.content?.string.hasPrefix("X") == true })
            #expect(harness.files.allSatisfy { $0.fileDocument != nil })
            #expect(harness.documents.allSatisfy { document in
                DreamderDocumentController.shared.documents.contains { $0 === document }
            })
        }
    }

    @Test
    func aWorkspaceWithoutEditedFilesAsksNothingAndMayCloseImmediately() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, names: ["a.txt"])
            defer { harness.close() }
            let confirmation = CloseConfirmationDouble(answering: .cancel)
            confirmation.install(on: harness.documents)
            let recorder = DocumentCloseRecorder()
            let context = ContextToken()

            harness.workspace.shouldCloseWindowController(
                NSWindowController(),
                delegate: recorder,
                shouldClose: DocumentCloseRecorder.selector,
                contextInfo: context.raw
            )

            #expect(confirmation.askedNames.isEmpty)
            #expect(recorder.calls.map(\.shouldClose) == [true])
        }
    }

    @Test
    func aWorkspaceWithoutAnEditorManagerReportsThatItCannotClose() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, names: ["a.txt"])
            defer { harness.close() }
            harness.workspace.editorManager = nil
            let recorder = DocumentCloseRecorder()
            let context = ContextToken()

            harness.workspace.shouldCloseWindowController(
                NSWindowController(),
                delegate: recorder,
                shouldClose: DocumentCloseRecorder.selector,
                contextInfo: context.raw
            )

            #expect(recorder.calls.map(\.shouldClose) == [false])
        }
    }

    @Test
    func closeRequestsWithoutACompleteCallbackReachNoDelegateAndKeepTheWindowOpen() throws {
        try withTempDir { directory in
            let workspace = WorkspaceDocument()
            try workspace.read(from: directory, ofType: "")
            workspace.makeWindowControllers()
            let controller = try #require(workspace.windowControllers.first)
            controller.window?.isReleasedWhenClosed = false
            defer {
                controller.window?.close()
                workspace.close()
            }
            let recorder = DocumentCloseRecorder()

            workspace.shouldCloseWindowController(controller, delegate: nil, shouldClose: nil, contextInfo: nil)
            workspace.shouldCloseWindowController(
                controller,
                delegate: recorder,
                shouldClose: nil,
                contextInfo: nil
            )
            workspace.shouldCloseWindowController(
                controller,
                delegate: nil,
                shouldClose: DocumentCloseRecorder.selector,
                contextInfo: nil
            )

            #expect(recorder.calls.isEmpty)
            #expect(workspace.windowControllers.count == 1)
            #expect(controller.window != nil)
        }
    }
}
