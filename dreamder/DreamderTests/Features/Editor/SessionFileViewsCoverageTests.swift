import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
private final class TriggerApplicationRecorder {
    var count = 0
    var characters: Set<String>?
    weak var reference: CodeFileViewControllerReference?

    func recordApplication() {
        count += 1
        characters = reference?.controller?.configuration.peripherals.codeSuggestionTriggerCharacters
    }
}

@MainActor
@Suite(.uiGate)
struct SessionFileViewsCoverageTests {
    private func makeFixture(in directory: URL, fileName: String = "Sample.swift") throws -> HostedSourceEditorFixture {
        try HostedSourceEditorFixture.make(
            in: directory,
            fileName: fileName,
            typeIdentifier: "public.swift-source",
            contents: "let a = 1\n"
        )
    }

    private func reference(of session: CodeFileViewSession) throws -> CodeFileViewControllerReference {
        try #require(session.coordinators.compactMap { $0 as? CodeFileViewControllerReference }.first)
    }

    @Test
    func requestedTriggerCharactersAreCommittedAfterTheControllerExistsWithTheDefaultCallback() async throws {
        try await withTempDir { directory in
            let fixture = try makeFixture(in: directory)
            let session = CodeFileViewSession(editorInstance: fixture.editorInstance, codeFile: fixture.document)
            let hosted = fixture.host(coordinators: [fixture.document.contentCoordinator] + session.coordinators)
            defer { hosted.close() }
            let sessionReference = try reference(of: session)
            try await eventually { sessionReference.controller != nil }

            let triggers: Set<String> = [".", "("]
            let immediate = session.completionTriggerCharacters(requested: triggers)
            #expect(immediate.isEmpty)

            try await eventually { session.completionTriggerCharacters(requested: triggers) == triggers }
            #expect(session.completionTriggerCharacters(requested: triggers) == triggers)
            withExtendedLifetime(session) {}
        }
    }

    @Test
    func applyingNotifiesTheCallbackAndReplacesPreviousTriggers() async throws {
        try await withTempDir { directory in
            let fixture = try makeFixture(in: directory)
            let recorder = TriggerApplicationRecorder()
            let session = CodeFileViewSession(
                editorInstance: fixture.editorInstance,
                codeFile: fixture.document
            ) { recorder.recordApplication() }
            let hosted = fixture.host(coordinators: [fixture.document.contentCoordinator] + session.coordinators)
            defer { hosted.close() }
            let sessionReference = try reference(of: session)
            recorder.reference = sessionReference
            try await eventually { sessionReference.controller != nil }

            _ = session.completionTriggerCharacters(requested: [".", "("])
            try await eventually { recorder.count == 1 }
            #expect(recorder.characters == [".", "("])

            _ = session.completionTriggerCharacters(requested: [":"])
            try await eventually { recorder.count == 2 }
            #expect(recorder.characters == [":"])
            withExtendedLifetime(session) {}
        }
    }

    @Test
    func controllerAlreadyHoldingTheRequestedCharactersIsLeftAlone() async throws {
        try await withTempDir { directory in
            let fixture = try makeFixture(in: directory)
            let recorder = TriggerApplicationRecorder()
            let session = CodeFileViewSession(
                editorInstance: fixture.editorInstance,
                codeFile: fixture.document
            ) { recorder.recordApplication() }
            let hosted = fixture.host(coordinators: [fixture.document.contentCoordinator] + session.coordinators)
            defer { hosted.close() }
            let sessionReference = try reference(of: session)
            recorder.reference = sessionReference
            try await eventually { sessionReference.controller != nil }
            let controller = try #require(sessionReference.controller)
            controller.configuration.peripherals.codeSuggestionTriggerCharacters = ["#"]

            _ = session.completionTriggerCharacters(requested: ["#"])
            try await eventually { recorder.count == 1 }

            #expect(recorder.characters == ["#"])
            withExtendedLifetime(session) {}
        }
    }

    @Test
    func applyingTriggersThroughTheStoreInvalidatesTheViewOnce() async throws {
        try await withTempDir { directory in
            let fixture = try makeFixture(in: directory)
            let store = CodeFileViewSessionStore()
            let session = store.session(editorInstance: fixture.editorInstance, codeFile: fixture.document)
            let hosted = fixture.host(coordinators: [fixture.document.contentCoordinator] + session.coordinators)
            defer { hosted.close() }
            let sessionReference = try reference(of: session)
            try await eventually { sessionReference.controller != nil }
            let before = store.generation

            _ = session.completionTriggerCharacters(requested: [".", "("])

            try await eventually { store.generation == before + 1 }
            #expect(store.session(editorInstance: fixture.editorInstance, codeFile: fixture.document) === session)
        }
    }

    @Test
    func controllerReferenceIsFilledByTheEditorAndClearedOnDestroy() async throws {
        try await withTempDir { directory in
            let fixture = try makeFixture(in: directory)
            let session = CodeFileViewSession(editorInstance: fixture.editorInstance, codeFile: fixture.document)
            let hosted = fixture.host(coordinators: [fixture.document.contentCoordinator] + session.coordinators)
            defer { hosted.close() }
            let sessionReference = try reference(of: session)

            try await eventually { sessionReference.controller != nil }
            #expect(sessionReference.controller === hosted.controller)

            sessionReference.destroy()

            #expect(sessionReference.controller == nil)
            withExtendedLifetime(session) {}
        }
    }

    @Test
    func textEditsMarkTheDocumentAsEdited() async throws {
        try await withTempDir { directory in
            let fixture = try makeFixture(in: directory)
            let session = CodeFileViewSession(editorInstance: fixture.editorInstance, codeFile: fixture.document)
            let hosted = fixture.host(coordinators: [fixture.document.contentCoordinator] + session.coordinators)
            defer { hosted.close() }
            try await eventually { hosted.controller?.textView?.window === hosted.window }
            #expect(!fixture.document.isDocumentEdited)

            let textView = try #require(hosted.controller?.textView)
            textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "x")

            try await eventually { fixture.document.isDocumentEdited }
            withExtendedLifetime(session) {}
        }
    }

    @Test
    func markdownDocumentsGetTheTypingCoordinatorAndHighlightProvider() async throws {
        try withTempDir { directory in
            let markdown = try makeFixture(in: directory, fileName: "Doc.md")
            let code = try makeFixture(in: directory, fileName: "Code.swift")

            let markdownSession = CodeFileViewSession(
                editorInstance: markdown.editorInstance,
                codeFile: markdown.document
            )
            let codeSession = CodeFileViewSession(editorInstance: code.editorInstance, codeFile: code.document)

            #expect(markdownSession.markdownHighlightProvider != nil)
            #expect(markdownSession.coordinators.filter { $0 is MarkdownTypingCoordinator }.count == 1)
            #expect(markdownSession.coordinators.count == codeSession.coordinators.count + 1)
            #expect(codeSession.markdownHighlightProvider == nil)
            #expect(!codeSession.coordinators.contains { $0 is MarkdownTypingCoordinator })
        }
    }
}
