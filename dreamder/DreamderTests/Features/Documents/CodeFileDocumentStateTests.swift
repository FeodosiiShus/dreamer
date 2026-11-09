import AppKit
import Foundation
import Testing
import os
import UniformTypeIdentifiers
@testable import Dreamder

@concurrent
private func writeCoordinated(_ text: String, to url: URL) async throws {
    var coordinationError: NSError?
    var writeError: (any Error)?
    NSFileCoordinator(filePresenter: nil).coordinate(
        writingItemAt: url,
        options: .forReplacing,
        error: &coordinationError
    ) { target in
        do {
            try text.write(to: target, atomically: true, encoding: .utf8)
        } catch {
            writeError = error
        }
    }
    if let error = coordinationError ?? writeError {
        throw error
    }
}

@MainActor
private final class OpenRecorder {
    private let opened = OSAllocatedUnfairLock(initialState: Set<ObjectIdentifier>())
    private var token: NSObjectProtocol?

    init() {
        token = NotificationCenter.default.addObserver(
            forName: CodeFileDocument.didOpenNotification,
            object: nil,
            queue: nil
        ) { [opened] notification in
            guard let object = notification.object as AnyObject? else { return }
            let identifier = ObjectIdentifier(object)
            _ = opened.withLock { $0.insert(identifier) }
        }
    }

    func didOpen(_ document: CodeFileDocument) -> Bool {
        let identifier = ObjectIdentifier(document)
        return opened.withLock { $0.contains(identifier) }
    }

    isolated deinit {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

@MainActor
@Suite(.uiGate)
struct CodeFileDocumentStateTests {
    private static let latin1 = Data([0x63, 0x61, 0x66, 0xE9, 0x21])
    private static let binary = Data([0x61, 0x62, 0x00, 0x63, 0x64])
    static let global = GlobalIndent(style: .spaces, spaceCount: 4, tabWidth: 4)

    func writeRootConfig(in directory: URL, extra: String = "") throws {
        try "root = true\n\(extra)".write(
            to: directory.appending(path: ".editorconfig"),
            atomically: true,
            encoding: .utf8
        )
    }

    func makeDocument(
        in directory: URL,
        name: String = "file.txt",
        data: Data,
        type: String = "public.plain-text"
    ) throws -> CodeFileDocument {
        let url = directory.appending(path: name)
        try data.write(to: url)
        return try CodeFileDocument(for: url, withContentsOf: url, ofType: type)
    }

    func makeDocument(
        in directory: URL,
        name: String = "file.txt",
        text: String,
        type: String = "public.plain-text"
    ) throws -> CodeFileDocument {
        try makeDocument(in: directory, name: name, data: Data(text.utf8), type: type)
    }

    @Test
    func tenMegabyteFileOpensReadOnlyWithoutOpeningLanguageServices() throws {
        try withTempDir { dir in
            try writeRootConfig(in: dir)
            let recorder = OpenRecorder()
            let line = String(repeating: "x", count: 99) + "\n"
            let text = String(repeating: line, count: FileSizeLimit.intelligence / line.utf8.count + 1)
            let document = try makeDocument(in: dir, text: text)

            #expect(document.isTooLargeForIntelligence)
            #expect(document.isReadOnly)
            #expect(!document.isBinary)
            #expect(document.readError == nil)
            #expect(document.notice == .tooLarge(byteCount: text.utf8.count))
            #expect(document.content?.length == text.utf16.count)
            #expect(document.detectedIndent == nil)
            #expect(!recorder.didOpen(document))
            #expect(throws: CodeFileError.readOnly) { try document.data(ofType: "public.plain-text") }
            #expect(document.applySaveActions() == false)
        }
    }

    @Test
    func fileJustBelowTenMegabytesStaysEditableAndNotifiesLanguageServices() throws {
        try withTempDir { dir in
            try writeRootConfig(in: dir)
            let recorder = OpenRecorder()
            let line = String(repeating: "x", count: 99) + "\n"
            let text = String(repeating: line, count: FileSizeLimit.intelligence / line.utf8.count - 1)
            let document = try makeDocument(in: dir, text: text)

            #expect(!document.isTooLargeForIntelligence)
            #expect(!document.isReadOnly)
            #expect(document.notice == nil)
            #expect(recorder.didOpen(document))
            #expect(throws: Never.self) { try document.data(ofType: "public.plain-text") }
        }
    }

    @Test
    func binaryFileOpensAsReadOnlyPlainText() throws {
        try withTempDir { dir in
            try writeRootConfig(in: dir)
            let recorder = OpenRecorder()
            let document = try makeDocument(in: dir, name: "blob.bin", data: Self.binary, type: "public.data")

            #expect(document.isBinary)
            #expect(document.isReadOnly)
            #expect(document.notice == .binary)
            #expect(document.readError == nil)
            #expect(document.content?.string == "ab\u{2400}cd")
            #expect(document.sourceEncoding == nil)
            #expect(document.utType?.conforms(to: .text) == true)
            #expect(!recorder.didOpen(document))
            #expect(throws: CodeFileError.readOnly) { try document.data(ofType: "public.data") }
            #expect(document.applySaveActions() == false)
        }
    }

    @Test
    func previewableBinaryKeepsNoContentAndItsOwnType() throws {
        try withTempDir { dir in
            let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49])
            let document = try makeDocument(in: dir, name: "pic.png", data: png, type: "public.png")

            #expect(document.content == nil)
            #expect(document.isBinary)
            #expect(document.readError == nil)
            #expect(document.utType?.conforms(to: .image) == true)
            #expect(document.utType?.conforms(to: .text) == false)
        }
    }

    @Test
    func undecodableTextProducesAnExplicitReadError() throws {
        try withTempDir { dir in
            try writeRootConfig(in: dir)
            let recorder = OpenRecorder()
            let document = try makeDocument(in: dir, name: "latin.txt", data: Self.latin1)

            #expect(document.readError == .undecodable)
            #expect(document.notice == .readError(.undecodable))
            #expect(document.content == nil)
            #expect(document.sourceEncoding == nil)
            #expect(document.isReadOnly)
            #expect(!document.isBinary)
            #expect(document.utType?.conforms(to: .text) == true)
            #expect(!recorder.didOpen(document))
            #expect(throws: CodeFileError.readOnly) { try document.data(ofType: "public.plain-text") }
        }
    }

    @Test
    func emptyFileOpensAsAnEmptyEditableDocument() throws {
        try withTempDir { dir in
            let document = try makeDocument(in: dir, data: Data())

            #expect(document.content?.string == "")
            #expect(document.sourceEncoding == .utf8)
            #expect(!document.isReadOnly)
            #expect(document.readError == nil)
            #expect(document.notice == nil)
        }
    }

    @Test
    func plainTextOpensEditableAndAnnouncesItself() throws {
        try withTempDir { dir in
            let recorder = OpenRecorder()
            let document = try makeDocument(in: dir, text: "hello\n")

            #expect(document.content?.string == "hello\n")
            #expect(document.sourceEncoding == .utf8)
            #expect(!document.isReadOnly)
            #expect(document.notice == nil)
            #expect(document.utType == .text)
            #expect(recorder.didOpen(document))
            #expect(throws: Never.self) { try document.data(ofType: "public.plain-text") }
        }
    }

    @Test
    func reloadingFromDiskMovesBetweenTheStates() async throws {
        try await withTempDir { dir in
            try writeRootConfig(in: dir)
            let document = try makeDocument(in: dir, text: "a\n  b\n  c\n")
            let url = try #require(document.fileURL)
            #expect(document.detectedIndent == .spaces(size: 2))

            try Self.latin1.write(to: url)
            document.presentedItemDidChange()
            try await eventually(timeout: .seconds(20)) { document.readError == .undecodable }
            #expect(document.content == nil)
            #expect(document.detectedIndent == nil)
            #expect(document.isReadOnly)

            try "a\n\tb\n\tc\n".write(to: url, atomically: true, encoding: .utf8)
            document.presentedItemDidChange()
            try await eventually(timeout: .seconds(20)) { document.content?.string == "a\n\tb\n\tc\n" }
            #expect(document.readError == nil)
            #expect(document.detectedIndent == .tabs)
            #expect(!document.isReadOnly)

            try Self.binary.write(to: url)
            document.presentedItemDidChange()
            try await eventually(timeout: .seconds(20)) { document.isBinary }
            #expect(document.isReadOnly)
            #expect(document.detectedIndent == nil)
        }
    }

    @Test
    func presenterNotificationsFromOtherThreadsReloadOnMainWithoutBlocking() async throws {
        try await withTempDir { dir in
            let document = try makeDocument(in: dir, text: "before\n")
            let url = try #require(document.fileURL)
            let registeredHere = !NSFileCoordinator.filePresenters.contains { $0 === document }
            if registeredHere {
                NSFileCoordinator.addFilePresenter(document)
            }
            defer {
                if registeredHere {
                    NSFileCoordinator.removeFilePresenter(document)
                }
            }

            try await writeCoordinated("after\n", to: url)

            try await eventually { document.content?.string == "after\n" }
        }
    }

    @Test
    func indentIsDetectedFromTheContentOnOpen() throws {
        try withTempDir { dir in
            try writeRootConfig(in: dir)
            let spaces = try makeDocument(in: dir, name: "s.txt", text: "a {\n  b\n  c\n}\n")
            let tabs = try makeDocument(in: dir, name: "t.txt", text: "a {\n\tb\n\tc\n}\n")
            let none = try makeDocument(in: dir, name: "n.txt", text: "a\nb\n")

            #expect(spaces.detectedIndent == .spaces(size: 2))
            #expect(tabs.detectedIndent == .tabs)
            #expect(none.detectedIndent == nil)
        }
    }

    @Test
    func editorConfigIsResolvedFromTheAncestorFilesOnOpen() throws {
        try withTempDir { dir in
            try writeRootConfig(
                in: dir,
                extra: "[*.txt]\nindent_style = tab\ntab_width = 3\ninsert_final_newline = true\n"
                    + "trim_trailing_whitespace = true\n"
            )
            let document = try makeDocument(in: dir, text: "a\n")

            #expect(
                document.editorConfig == EditorConfigProperties(
                    indentStyle: .tab,
                    indentSize: 3,
                    tabWidth: 3,
                    insertFinalNewline: true,
                    trimTrailingWhitespace: true
                )
            )
        }
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct CodeFileDocumentSaveEntryPointTests {
    @Test
    func saveActionAppliesBeforeTheSystemSaveRuns() async throws {
        try await withTempDir { dir in
            try "root = true\n[*.txt]\ntrim_trailing_whitespace = true\n".write(
                to: dir.appending(path: ".editorconfig"),
                atomically: true,
                encoding: .utf8
            )
            let url = dir.appending(path: "save.txt")
            try "a  \nb  \n".write(to: url, atomically: true, encoding: .utf8)
            let document = try CodeFileDocument(for: url, withContentsOf: url, ofType: "public.plain-text")
            document.updateChangeCount(.changeDone)

            document.save(nil)

            try await eventually { (try? Data(contentsOf: url)) == Data("a\nb\n".utf8) }
            #expect(document.content?.string == "a\nb\n")
        }
    }

    @Test
    func scheduledAutosaveAppliesSaveActionsFirst() async throws {
        try await withTempDir { dir in
            try "root = true\n[*.txt]\ntrim_trailing_whitespace = true\n".write(
                to: dir.appending(path: ".editorconfig"),
                atomically: true,
                encoding: .utf8
            )
            let url = dir.appending(path: "auto.txt")
            try "a  \n".write(to: url, atomically: true, encoding: .utf8)
            let document = try CodeFileDocument(for: url, withContentsOf: url, ofType: "public.plain-text")
            document.autosavingInPlace = { true }
            document.autosavedContentsFileURL = dir.appending(path: "autosaved.txt")
            document.updateChangeCount(.changeDone)

            document.scheduleAutosaving()

            try await eventually(timeout: .seconds(30)) { document.content?.string == "a\n" }
        }
    }
}
