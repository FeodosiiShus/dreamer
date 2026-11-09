import AppKit
import Foundation
import Testing
@testable import Dreamder

private actor WindowLoaderGate {
    private var isOpen = false
    private var entered = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var hasEntered: Bool { entered }

    func pass() async {
        entered = true
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct NSDocumentControllerEditorWindowTests {
    private func registeredDocuments(for url: URL) -> [CodeFileDocument] {
        let target = url.resolvingSymlinksInPath().path(percentEncoded: false)
        return NSDocumentController.shared.documents
            .compactMap { $0 as? CodeFileDocument }
            .filter { $0.fileURL?.resolvingSymlinksInPath().path(percentEncoded: false) == target }
    }

    private func discard(_ documents: [CodeFileDocument]) {
        for document in documents {
            document.windowControllers.forEach { $0.window?.isReleasedWhenClosed = false }
            document.close()
        }
    }

    private func gatedLoader(_ gate: WindowLoaderGate) -> CodeFileDiskLoader.Loader {
        { url, fileTypeName in
            await gate.pass()
            return try await CodeFileDiskLoader.read(from: url, fileTypeName: fileTypeName)
        }
    }

    @Test
    func theFileIsReadBeforeTheDocumentIsRegisteredAndShown() async throws {
        try await withTempDir { directory in
            let url = directory.appending(path: "window.txt")
            try "window text\n".write(to: url, atomically: true, encoding: .utf8)
            let file = CEWorkspaceFile(url: url)
            let gate = WindowLoaderGate()
            let loader = gatedLoader(gate)
            let opening = Task {
                try await NSDocumentController.shared.openInNewEditorWindow(file, loader: loader)
            }
            try await eventually(timeout: .seconds(20)) { await gate.hasEntered }

            #expect(file.fileDocument == nil)
            #expect(registeredDocuments(for: url).isEmpty)

            await gate.open()
            try await opening.value

            let documents = registeredDocuments(for: url)
            defer { discard(documents) }
            let document = try #require(documents.first)
            #expect(documents.count == 1)
            #expect(file.fileDocument === document)
            #expect(document.content?.string == "window text\n")
            #expect(!document.windowControllers.isEmpty)
        }
    }

    @Test
    func aDocumentThatAppearsWhileTheFileIsBeingReadIsReusedAndTheCopyIsDropped() async throws {
        try await withTempDir { directory in
            let url = directory.appending(path: "race.txt")
            try "race text\n".write(to: url, atomically: true, encoding: .utf8)
            let file = CEWorkspaceFile(url: url)
            let gate = WindowLoaderGate()
            let loader = gatedLoader(gate)
            let opening = Task {
                try await NSDocumentController.shared.openInNewEditorWindow(file, loader: loader)
            }
            try await eventually(timeout: .seconds(20)) { await gate.hasEntered }
            let winner = try CodeFileDocument(contentsOf: url, ofType: "public.plain-text")
            file.fileDocument = winner
            defer { discard([winner]) }

            await gate.open()
            try await opening.value

            #expect(file.fileDocument === winner)
            #expect(registeredDocuments(for: url).isEmpty)
            #expect(!winner.windowControllers.isEmpty)
        }
    }

    @Test
    func anAlreadyLoadedDocumentIsShownWithoutReadingTheFileAgain() async throws {
        try await withTempDir { directory in
            let url = directory.appending(path: "loaded.txt")
            try "loaded text\n".write(to: url, atomically: true, encoding: .utf8)
            let file = CEWorkspaceFile(url: url)
            let loaded = try CodeFileDocument(contentsOf: url, ofType: "public.plain-text")
            file.fileDocument = loaded
            defer { discard([loaded]) }
            let loader: CodeFileDiskLoader.Loader = { _, _ in throw CocoaError(.fileReadUnknown) }

            try await NSDocumentController.shared.openInNewEditorWindow(file, loader: loader)

            #expect(!loaded.windowControllers.isEmpty)
            #expect(file.fileDocument === loaded)
        }
    }
}
