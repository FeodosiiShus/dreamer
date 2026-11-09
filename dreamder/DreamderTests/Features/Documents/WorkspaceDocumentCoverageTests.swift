import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
private final class ConfirmationLog {
    var fileNames: [String] = []
}

@MainActor
@Suite(.serialized, .uiGate)
struct WorkspaceDocumentCoverageTests {
    @MainActor
    private struct Harness {
        let workspace: WorkspaceDocument
        let documents: [CodeFileDocument]

        func close() {
            documents.forEach { $0.close() }
            workspace.close()
        }

        func markEdited(confirming log: ConfirmationLog, accepting: Bool) {
            for document in documents {
                document.updateChangeCount(.changeDone)
                document.closeConfirmation = { edited in
                    log.fileNames.append(edited.fileURL?.lastPathComponent ?? "")
                    if accepting {
                        edited.updateChangeCount(.changeCleared)
                    }
                    return accepting
                }
            }
        }
    }

    private func makeHarness(in directory: URL, names: [String]) throws -> Harness {
        for name in names {
            try "text of \(name)\n".write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
        }
        let workspace = WorkspaceDocument()
        try workspace.read(from: directory, ofType: "")
        let manager = try #require(workspace.editorManager)
        var documents: [CodeFileDocument] = []
        for name in names {
            let path = directory.appending(path: name).path(percentEncoded: false)
            let file = try #require(workspace.workspaceFileManager?.getFile(path, createIfNotFound: true))
            manager.openTab(item: file)
            documents.append(try #require(file.fileDocument))
        }
        return Harness(workspace: workspace, documents: documents)
    }

    @Test
    func theStoredWindowFrameIsRestoredWhenTheWindowIsCreated() throws {
        try withTempDir { directory in
            let workspace = WorkspaceDocument()
            try workspace.read(from: directory, ofType: "")
            let workspaceURL = try #require(workspace.fileURL)
            let stateKey = "workspaceState-\(workspaceURL.absoluteString)"
            let stored = NSRect(x: 40, y: 60, width: 1000, height: 700)
            workspace.addToWorkspaceState(key: .workspaceWindowSize, value: NSStringFromRect(stored))

            let window = workspace.makeWorkspaceWindow()
            window.isReleasedWhenClosed = false
            defer {
                window.close()
                workspace.close()
                UserDefaults.standard.removeObject(forKey: stateKey)
            }
            #expect(window.frame.size == stored.size)
        }
    }

    @Test
    func readingWithoutAnEditorManagerFailsWithAReadError() throws {
        try withTempDir { directory in
            let workspace = WorkspaceDocument()
            workspace.editorManager = nil

            let error = #expect(throws: CocoaError.self) { try workspace.read(from: directory, ofType: "") }

            #expect(error?.code == .fileReadUnknown)
        }
    }

    @Test
    func writingAWorkspaceCreatesNothing() throws {
        try withTempDir { directory in
            let workspace = WorkspaceDocument()
            let target = directory.appending(path: "workspace.out")

            try workspace.write(to: target, ofType: "")

            #expect(!FileManager.default.fileExists(atPath: target.path))
        }
    }

    @Test
    func theCloseDecisionIsStoredThroughTheContextPointer() {
        let workspace = WorkspaceDocument()
        let context = ContextToken(initial: true)

        workspace.document(NSDocument(), shouldClose: false, contextInfo: context.raw)
        #expect(context.pointer.pointee == false)

        workspace.document(NSDocument(), shouldClose: true, contextInfo: context.raw)
        #expect(context.pointer.pointee == true)
    }

    @Test
    func everyEditedFileIsConfirmedAndTheDelegateLearnsTheWorkspaceIsClean() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, names: ["a.txt", "b.txt"])
            defer { harness.close() }
            let log = ConfirmationLog()
            harness.markEdited(confirming: log, accepting: true)
            let recorder = DocumentCloseRecorder()
            let context = ContextToken()

            harness.workspace.shouldCloseWindowController(
                NSWindowController(),
                delegate: recorder,
                shouldClose: DocumentCloseRecorder.selector,
                contextInfo: context.raw
            )

            #expect(log.fileNames.sorted() == ["a.txt", "b.txt"])
            #expect(recorder.calls.map(\.shouldClose) == [true])
            #expect(recorder.calls.first?.document === harness.workspace)
            #expect(recorder.calls.first?.contextInfo == context.raw)
        }
    }

    @Test
    func cancellingTheFirstConfirmationStopsAskingAndKeepsTheWorkspaceOpen() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, names: ["a.txt", "b.txt"])
            defer { harness.close() }
            let log = ConfirmationLog()
            harness.markEdited(confirming: log, accepting: false)
            let recorder = DocumentCloseRecorder()
            let context = ContextToken()

            harness.workspace.shouldCloseWindowController(
                NSWindowController(),
                delegate: recorder,
                shouldClose: DocumentCloseRecorder.selector,
                contextInfo: context.raw
            )

            #expect(log.fileNames.count == 1)
            #expect(recorder.calls.map(\.shouldClose) == [false])
        }
    }

    @Test
    func aWorkspaceWithoutEditedFilesAsksNothingAndMayClose() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, names: ["a.txt"])
            defer { harness.close() }
            let log = ConfirmationLog()
            harness.documents.forEach { document in
                document.closeConfirmation = { edited in
                    log.fileNames.append(edited.fileURL?.lastPathComponent ?? "")
                    return false
                }
            }
            let recorder = DocumentCloseRecorder()
            let context = ContextToken()

            harness.workspace.shouldCloseWindowController(
                NSWindowController(),
                delegate: recorder,
                shouldClose: DocumentCloseRecorder.selector,
                contextInfo: context.raw
            )

            #expect(log.fileNames.isEmpty)
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
    func aCloseRequestWithoutContextInfoIsHandledByTheSystem() async throws {
        try await withTempDir { directory in
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

            workspace.shouldCloseWindowController(
                controller,
                delegate: recorder,
                shouldClose: DocumentCloseRecorder.selector,
                contextInfo: nil
            )

            try await eventually(timeout: .seconds(30)) { recorder.calls.count == 1 }
            #expect(recorder.calls.first?.shouldClose == true)
        }
    }
}
