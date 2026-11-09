import AppKit
import CodeEditLanguages
import Foundation
import Observation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct CodeFileDocumentCoverageTests {
    private func makeDocument(
        in directory: URL,
        name: String = "file.txt",
        text: String = "hello\n"
    ) throws -> CodeFileDocument {
        let url = directory.appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return try CodeFileDocument(for: url, withContentsOf: url, ofType: "public.plain-text")
    }

    @Test
    func aDocumentThatWasNeverReadCannotBeEncoded() {
        let document = CodeFileDocument()

        #expect(throws: CodeFileError.failedToEncode) { try document.data(ofType: "public.plain-text") }
    }

    @Test
    func editedStateIsObservableAroundEditsAndSavesWhenAutosaveInPlaceIsOff() async throws {
        try await withTempDir { directory in
            let document = try makeDocument(in: directory)
            defer { document.close() }
            document.autosavingInPlace = { false }
            var states = Observations { document.isEdited }.makeAsyncIterator()

            #expect(await states.next(isolation: #isolation) == false)

            document.updateChangeCount(.changeDone)
            #expect(await states.next(isolation: #isolation) == true)

            let token = document.changeCountToken(for: .saveOperation)
            document.updateChangeCount(withToken: token, for: .saveOperation)
            #expect(await states.next(isolation: #isolation) == false)
        }
    }

    @Test
    func editedStateStaysCleanWhenAutosaveInPlaceIsOn() throws {
        try withTempDir { directory in
            let document = try makeDocument(in: directory)
            defer { document.close() }
            document.autosavingInPlace = { true }

            document.updateChangeCount(.changeDone)
            let token = document.changeCountToken(for: .saveOperation)
            document.updateChangeCount(withToken: token, for: .saveOperation)

            #expect(!document.isEdited)
        }
    }

    @Test
    func windowFrameMemoryIsReadFromTheGivenDefaults() throws {
        let isolated = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
        let url = URL(filePath: "/tmp/frame-memory/\(UUID().uuidString).txt")

        #expect(!CodeFileDocument.hasSavedWindowFrame(for: url, defaults: isolated.defaults))

        let frame = NSStringFromRect(NSRect(x: 1, y: 2, width: 300, height: 400))
        isolated.defaults.set(frame, forKey: "NSWindow Frame \(url.path)")

        #expect(CodeFileDocument.hasSavedWindowFrame(for: url, defaults: isolated.defaults))
    }

    @Test
    func theWindowOfAFirstOpenedFileIsCreatedWithItsContentAndFrameName() throws {
        try withTempDir { directory in
            let document = try makeDocument(in: directory)
            let url = try #require(document.fileURL)
            let frameKey = "NSWindow Frame \(url.path)"
            defer {
                UserDefaults.standard.removeObject(forKey: frameKey)
                document.close()
            }
            #expect(!CodeFileDocument.hasSavedWindowFrame(for: url))

            document.makeWindowControllers()

            let controller = try #require(document.windowControllers.first)
            let window = try #require(controller.window)
            window.isReleasedWhenClosed = false
            defer {
                controller.windowFrameAutosaveName = ""
                window.close()
            }
            #expect(document.windowControllers.count == 1)
            #expect(controller.windowFrameAutosaveName == url.path)
            #expect(controller.shouldCascadeWindows == false)
            #expect(window.contentView != nil)
            #expect(window.styleMask.contains(.fullSizeContentView))
        }
    }

    @Test
    func theWindowOfAFileWithoutLocationIsCreatedWithoutAFrameName() {
        let document = CodeFileDocument()
        defer { document.close() }

        document.makeWindowControllers()

        let controller = document.windowControllers.first
        controller?.window?.isReleasedWhenClosed = false
        defer { controller?.window?.close() }
        #expect(controller?.windowFrameAutosaveName == "")
        #expect(controller?.window?.contentView != nil)
    }

    @Test
    func savingWhenTheParentFolderCannotBePreparedPresentsTheErrorAndWritesNothing() throws {
        try withTempDir { directory in
            let document = try makeDocument(in: directory)
            defer { document.close() }
            let blocker = directory.appending(path: "blocker")
            try Data().write(to: blocker)
            let target = blocker.appending(path: "file.txt")
            document.fileURL = target
            document.updateChangeCount(.changeDone)
            let modalsBefore = DreamderHeadless.suppressedModals.count

            document.save(nil)

            #expect(DreamderHeadless.suppressedModals.count > modalsBefore)
            #expect(!FileManager.default.fileExists(atPath: target.path))
            #expect(document.isDocumentEdited)
        }
    }

    @Test
    func theMakeSourceTypeHasNoFileNameExtensionAndOtherTypesFollowTheSystem() {
        let document = CodeFileDocument()
        let system = NSDocument()

        #expect(document.fileNameExtension(forType: "public.make-source", saveOperation: .saveOperation) == nil)
        #expect(
            document.fileNameExtension(forType: "public.plain-text", saveOperation: .saveOperation)
                == system.fileNameExtension(forType: "public.plain-text", saveOperation: .saveOperation)
        )
    }

    @Test
    func aDocumentWithoutALocationHasTheDefaultLanguage() {
        #expect(CodeFileDocument().getLanguage().id.rawValue == CodeLanguage.default.id.rawValue)
    }

    @Test
    func aConfirmationAnsweredLaterReportsItsDecisionOnlyWhenItIsGiven() {
        let document = CodeFileDocument()
        defer { document.close() }
        document.autosavingInPlace = { false }
        document.updateChangeCount(.changeDone)
        let recorder = DocumentCloseRecorder()
        let context = ContextToken()
        let confirmation = CloseConfirmationDouble()
        confirmation.install(on: [document])

        document.canClose(withDelegate: recorder, shouldClose: DocumentCloseRecorder.selector, contextInfo: context.raw)
        document.canClose(withDelegate: recorder, shouldClose: DocumentCloseRecorder.selector, contextInfo: context.raw)

        #expect(recorder.calls.isEmpty)
        #expect(confirmation.pendingCount == 2)

        confirmation.answerNext(.cancel)
        confirmation.answerNext(.discard)

        #expect(recorder.calls.map(\.shouldClose) == [false, true])
        #expect(recorder.calls.allSatisfy { $0.document === document && $0.contextInfo == context.raw })
        #expect(document.isDocumentEdited)
    }

    @Test
    func savingThroughTheConfirmationCleansTheDocument() {
        let document = CodeFileDocument()
        defer { document.close() }
        document.autosavingInPlace = { false }
        document.updateChangeCount(.changeDone)
        let recorder = DocumentCloseRecorder()
        let confirmation = CloseConfirmationDouble()
        confirmation.install(on: [document])

        document.canClose(withDelegate: recorder, shouldClose: DocumentCloseRecorder.selector, contextInfo: nil)
        confirmation.answerNext(.save)

        #expect(recorder.calls.map(\.shouldClose) == [true])
        #expect(!document.isDocumentEdited)
    }

    @Test
    func closingACleanDocumentSkipsTheConfirmationAndAllowsTheClose() async throws {
        let document = CodeFileDocument()
        defer { document.close() }
        let recorder = DocumentCloseRecorder()
        let context = ContextToken()
        let confirmation = CloseConfirmationDouble(answering: .cancel)
        confirmation.install(on: [document])

        document.canClose(withDelegate: recorder, shouldClose: DocumentCloseRecorder.selector, contextInfo: context.raw)

        try await eventually(timeout: .seconds(30)) { recorder.calls.count == 1 }
        #expect(recorder.calls.first?.shouldClose == true)
        #expect(confirmation.askedNames.isEmpty)
    }

    @Test
    func aDocumentWithItsOwnWindowIsInUseOutsideEveryWorkspace() throws {
        try withTempDir { directory in
            let document = try makeDocument(in: directory)
            defer { document.close() }
            let workspace = WorkspaceDocument()
            #expect(!document.isInUse(outside: workspace))

            document.addWindowController(NSWindowController())
            #expect(document.isInUse(outside: workspace))
        }
    }
}
