import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct WorkspaceDocumentCoverageTests {
    @MainActor
    struct Harness {
        let workspace: WorkspaceDocument
        let files: [CEWorkspaceFile]
        let documents: [CodeFileDocument]

        func close() {
            workspace.close()
            if let url = workspace.fileURL {
                UserDefaults.standard.removeObject(forKey: WorkspaceDocument.workspaceStateKey(for: url))
            }
        }

        func markEdited(using confirmation: CloseConfirmationDouble) {
            for document in documents {
                document.autosavingInPlace = { false }
                document.content?.replaceCharacters(in: NSRange(location: 0, length: 0), with: "X")
                document.updateChangeCount(.changeDone)
            }
            confirmation.install(on: documents)
        }
    }

    func makeHarness(in directory: URL, names: [String]) throws -> Harness {
        for name in names {
            try "text of \(name)\n".write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
        }
        let workspace = WorkspaceDocument()
        try workspace.read(from: directory, ofType: "")
        let manager = try #require(workspace.editorManager)
        var files: [CEWorkspaceFile] = []
        var documents: [CodeFileDocument] = []
        for name in names {
            let path = directory.appending(path: name).path(percentEncoded: false)
            let file = try #require(workspace.workspaceFileManager?.getFile(path, createIfNotFound: true))
            manager.openTab(item: file)
            files.append(file)
            documents.append(try #require(file.fileDocument))
        }
        return Harness(workspace: workspace, files: files, documents: documents)
    }

    private func openDocuments(for url: URL) -> [CodeFileDocument] {
        DreamderDocumentController.shared.documents
            .compactMap { $0 as? CodeFileDocument }
            .filter { $0.fileURL?.standardizedFileURL == url.standardizedFileURL }
    }

    @Test
    func theStoredWindowFrameIsRestoredWhenTheWindowIsCreated() throws {
        try withTempDir { directory in
            let workspace = WorkspaceDocument()
            try workspace.read(from: directory, ofType: "")
            let workspaceURL = try #require(workspace.fileURL)
            let stateKey = WorkspaceDocument.workspaceStateKey(for: workspaceURL)
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
    func theStateKeyIsBuiltFromTheStandardizedUrl() {
        let url = URL(filePath: "/work/./a/../b/", directoryHint: .isDirectory)
        let key = WorkspaceDocument.workspaceStateKey(for: url)

        #expect(key == "workspaceState-file:///work/b/")
    }

    @Test
    func aWorkspaceWithoutALocationKeepsItsStateInMemoryAndPersistsNothing() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let first = WorkspaceDocument()
        let second = WorkspaceDocument()
        first.stateDefaults = defaults
        second.stateDefaults = defaults

        first.addToWorkspaceState(key: .workspaceWindowSize, value: "stored")

        #expect(first.getFromWorkspaceState(.workspaceWindowSize) as? String == "stored")
        #expect(second.getFromWorkspaceState(.workspaceWindowSize) == nil)
        #expect(!defaults.dictionaryRepresentation().keys.contains { $0.hasPrefix("workspaceState-") })

        first.addToWorkspaceState(key: .workspaceWindowSize, value: nil)

        #expect(first.getFromWorkspaceState(.workspaceWindowSize) == nil)
    }

    @Test
    func aWorkspaceWithALocationPersistsItsStateInTheInjectedDefaults() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let location = URL(filePath: "/work/injected", directoryHint: .isDirectory)
        let workspace = WorkspaceDocument()
        workspace.fileURL = location
        workspace.stateDefaults = defaults

        workspace.addToWorkspaceState(key: .workspaceWindowSize, value: "stored")

        let stored = defaults.object(forKey: WorkspaceDocument.workspaceStateKey(for: location)) as? [String: Any]
        #expect(workspace.getFromWorkspaceState(.workspaceWindowSize) as? String == "stored")
        #expect(stored?[WorkspaceStateKey.workspaceWindowSize.rawValue] as? String == "stored")
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
    func closingAWorkspaceClosesItsDocumentsAndReopeningLeavesOneDocumentPerUrl() throws {
        try withTempDir { directory in
            let url = directory.appending(path: "a.txt")
            let first = try makeHarness(in: directory, names: ["a.txt"])
            #expect(openDocuments(for: url).count == 1)

            first.close()

            #expect(openDocuments(for: url).isEmpty)
            #expect(first.files.allSatisfy { $0.fileDocument == nil })

            let second = try makeHarness(in: directory, names: ["a.txt"])
            defer { second.close() }

            #expect(openDocuments(for: url).count == 1)
            #expect(openDocuments(for: url).first === second.documents.first)
        }
    }

    @Test
    func loadingTheSameUrlTwiceReusesTheOpenDocument() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, names: ["a.txt"])
            defer { harness.close() }
            let url = directory.appending(path: "a.txt")
            let another = CEWorkspaceFile(url: url)

            try another.loadCodeFile()

            #expect(another.fileDocument === harness.documents.first)
            #expect(openDocuments(for: url).count == 1)
        }
    }

    @Test
    func aDocumentStaysOpenWhileAnotherOpenWorkspaceStillShowsIt() throws {
        try withTempDir { directory in
            let url = directory.appending(path: "a.txt")
            let first = try makeHarness(in: directory, names: ["a.txt"])
            let second = try makeHarness(in: directory, names: ["a.txt"])
            defer { second.close() }
            let document = try #require(first.documents.first)
            let secondDocument = try #require(second.documents.first)
            DreamderDocumentController.shared.addDocument(first.workspace)
            DreamderDocumentController.shared.addDocument(second.workspace)

            #expect(document === secondDocument)
            #expect(document.isInUse(outside: first.workspace))
            #expect(first.workspace.isShowing(document))

            let firstFile = try #require(first.files.first)
            try #require(first.workspace.editorManager).activeEditor.closeTab(file: firstFile)

            #expect(openDocuments(for: url).count == 1)

            first.close()

            #expect(openDocuments(for: url).count == 1)
            #expect(!document.isInUse(outside: second.workspace))
        }
    }

    @Test
    func aClosedWorkspaceShowsNoDocument() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, names: ["a.txt"])
            let document = try #require(harness.documents.first)
            #expect(harness.workspace.isShowing(document))

            harness.close()

            #expect(harness.workspace.editorManager == nil)
            #expect(!harness.workspace.isShowing(document))
        }
    }
}
