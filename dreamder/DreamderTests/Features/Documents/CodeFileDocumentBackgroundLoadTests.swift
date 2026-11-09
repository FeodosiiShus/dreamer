import Foundation
import Testing
@testable import Dreamder

private actor LoaderGate {
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

private struct LoaderFailure: Error {}

@MainActor
@Suite(.serialized, .uiGate)
struct CodeFileDocumentBackgroundLoadTests {
    private static let plainText = "public.plain-text"

    private func makeDocument(in directory: URL, text: String = "before\n") throws -> CodeFileDocument {
        let url = directory.appending(path: "load.txt")
        try text.write(to: url, atomically: true, encoding: .utf8)
        let document = try CodeFileDocument(contentsOf: url, ofType: Self.plainText)
        document.autosavingInPlace = { false }
        return document
    }

    private func gatedLoader(_ gate: LoaderGate) -> CodeFileDiskLoader.Loader {
        { url, fileTypeName in
            await gate.pass()
            return try await CodeFileDiskLoader.read(from: url, fileTypeName: fileTypeName)
        }
    }

    private func stamp(_ url: URL, at seconds: TimeInterval) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: seconds)],
            ofItemAtPath: url.path(percentEncoded: false)
        )
    }

    @Test
    func classifyingTextDetectsItsIndent() {
        let loaded = CodeFileDiskLoader.classify(
            data: Data("a {\n  b\n  c\n}\n".utf8),
            fileTypeName: Self.plainText
        )

        #expect(loaded.content.text == "a {\n  b\n  c\n}\n")
        #expect(loaded.content.encoding == .utf8)
        #expect(loaded.detectedIndent == .spaces(size: 2))
        #expect(!loaded.content.state.isReadOnly)
    }

    @Test
    func classifyingBinaryDataDetectsNoIndent() {
        let loaded = CodeFileDiskLoader.classify(
            data: Data([0x61, 0x20, 0x20, 0x00, 0x0A, 0x20, 0x20, 0x62, 0x0A, 0x20, 0x20, 0x63, 0x0A]),
            fileTypeName: "public.data"
        )

        #expect(loaded.content.state.isBinary)
        #expect(loaded.detectedIndent == nil)
    }

    @Test
    func readingAFileOffTheMainActorClassifiesItsBytes() async throws {
        try await withTempDir { dir in
            let url = dir.appending(path: "read.txt")
            try "a {\n\tb\n\tc\n}\n".write(to: url, atomically: true, encoding: .utf8)

            let loaded = try await CodeFileDiskLoader.read(from: url, fileTypeName: Self.plainText)

            #expect(loaded.content.text == "a {\n\tb\n\tc\n}\n")
            #expect(loaded.detectedIndent == .tabs)
        }
    }

    @Test
    func readingAMissingFileThrows() async throws {
        try await withTempDir { dir in
            let missing = dir.appending(path: "missing.txt")

            await #expect(throws: CocoaError.self) {
                try await CodeFileDiskLoader.read(from: missing, fileTypeName: Self.plainText)
            }
            await #expect(throws: CocoaError.self) {
                try await CodeFileDiskLoader.live(missing, Self.plainText)
            }
        }
    }

    @Test
    func anExternalReloadReadsOffTheMainActorAndAppliesAfterwards() async throws {
        try await withTempDir { dir in
            let document = try makeDocument(in: dir)
            defer { document.close() }
            let url = try #require(document.fileURL)
            let gate = LoaderGate()
            document.diskLoader = gatedLoader(gate)
            try "after\n".write(to: url, atomically: true, encoding: .utf8)

            document.presentedItemDidChange()
            try await eventually(timeout: .seconds(20)) { await gate.hasEntered }

            #expect(document.content?.string == "before\n")
            await gate.open()
            try await eventually(timeout: .seconds(20)) { document.content?.string == "after\n" }
            #expect(document.reloadTask == nil)
        }
    }

    @Test
    func aNewerChangeSupersedesAReloadThatIsStillReading() async throws {
        try await withTempDir { dir in
            let document = try makeDocument(in: dir)
            defer { document.close() }
            let url = try #require(document.fileURL)
            let gate = LoaderGate()
            document.diskLoader = gatedLoader(gate)
            try "first\n".write(to: url, atomically: true, encoding: .utf8)
            try stamp(url, at: 1_000)
            document.presentedItemDidChange()
            let firstReload = try #require(document.reloadTask)
            try await eventually(timeout: .seconds(20)) { await gate.hasEntered }

            document.diskLoader = CodeFileDiskLoader.live
            try "second\n".write(to: url, atomically: true, encoding: .utf8)
            try stamp(url, at: 2_000)
            document.presentedItemDidChange()
            let secondReload = try #require(document.reloadTask)
            await secondReload.value
            #expect(document.content?.string == "second\n")

            await gate.open()
            await firstReload.value
            #expect(document.content?.string == "second\n")
        }
    }

    @Test
    func aReloadDoesNotOverwriteEditsMadeWhileItWasReading() async throws {
        try await withTempDir { dir in
            let document = try makeDocument(in: dir)
            defer { document.close() }
            let url = try #require(document.fileURL)
            let modifiedBefore = document.fileModificationDate
            let gate = LoaderGate()
            document.diskLoader = gatedLoader(gate)
            try "after\n".write(to: url, atomically: true, encoding: .utf8)
            document.presentedItemDidChange()
            let reload = try #require(document.reloadTask)
            try await eventually(timeout: .seconds(20)) { await gate.hasEntered }

            document.updateChangeCount(.changeDone)
            await gate.open()
            await reload.value

            #expect(document.content?.string == "before\n")
            #expect(document.fileModificationDate == modifiedBefore)
            #expect(document.isDocumentEdited)
        }
    }

    @Test
    func aFailedReadLeavesTheDocumentAsItWas() async throws {
        try await withTempDir { dir in
            let document = try makeDocument(in: dir)
            defer { document.close() }
            let url = try #require(document.fileURL)
            let modifiedBefore = document.fileModificationDate
            document.diskLoader = { _, _ in throw LoaderFailure() }
            try "after\n".write(to: url, atomically: true, encoding: .utf8)

            document.presentedItemDidChange()
            let reload = try #require(document.reloadTask)
            await reload.value

            #expect(document.content?.string == "before\n")
            #expect(document.fileModificationDate == modifiedBefore)
        }
    }

    @Test
    func closingTheDocumentCancelsAReloadThatIsStillReading() async throws {
        try await withTempDir { dir in
            let document = try makeDocument(in: dir)
            let url = try #require(document.fileURL)
            let gate = LoaderGate()
            document.diskLoader = gatedLoader(gate)
            try "after\n".write(to: url, atomically: true, encoding: .utf8)
            document.presentedItemDidChange()
            let reload = try #require(document.reloadTask)
            try await eventually(timeout: .seconds(20)) { await gate.hasEntered }

            document.close()
            #expect(document.reloadTask == nil)
            await gate.open()
            await reload.value

            #expect(document.content?.string == "before\n")
        }
    }

    @Test
    func anUnchangedFileDoesNotStartAReload() throws {
        try withTempDir { dir in
            let document = try makeDocument(in: dir)
            defer { document.close() }

            document.presentedItemDidChange()

            #expect(document.reloadTask == nil)
            #expect(document.content?.string == "before\n")
        }
    }

    @Test
    func openingAFileReadsOffTheMainActorAndBuildsTheDocumentAfterwards() async throws {
        try await withTempDir { dir in
            try "root = true\n[*.txt]\ntrim_trailing_whitespace = true\n".write(
                to: dir.appending(path: ".editorconfig"),
                atomically: true,
                encoding: .utf8
            )
            let url = dir.appending(path: "opened.txt")
            try "a {\n  b\n  c\n}\n".write(to: url, atomically: true, encoding: .utf8)
            let gate = LoaderGate()
            let loader = gatedLoader(gate)
            let opening = Task {
                try await CodeFileDocument.open(contentsOf: url, ofType: Self.plainText, loader: loader)
            }
            try await eventually(timeout: .seconds(20)) { await gate.hasEntered }

            await gate.open()
            let document = try await opening.value
            defer { document.close() }

            #expect(document.content?.string == "a {\n  b\n  c\n}\n")
            #expect(document.fileURL == url)
            #expect(document.fileType == Self.plainText)
            #expect(document.detectedIndent == .spaces(size: 2))
            #expect(document.editorConfig.trimTrailingWhitespace == true)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
            let modified = attributes[.modificationDate] as? Date
            #expect(document.fileModificationDate == modified)
        }
    }

    @Test
    func openingAFileWithTheDefaultLoaderMatchesTheSynchronousInitializer() async throws {
        try await withTempDir { dir in
            let url = dir.appending(path: "same.txt")
            try "hello\n".write(to: url, atomically: true, encoding: .utf8)

            let opened = try await CodeFileDocument.open(contentsOf: url, ofType: Self.plainText)
            defer { opened.close() }
            let synchronous = try CodeFileDocument(contentsOf: url, ofType: Self.plainText)
            defer { synchronous.close() }

            #expect(opened.content?.string == synchronous.content?.string)
            #expect(opened.sourceEncoding == synchronous.sourceEncoding)
            #expect(opened.contentState == synchronous.contentState)
            #expect(opened.fileModificationDate == synchronous.fileModificationDate)
        }
    }

    @Test
    func openingAnUndecodableFileProducesAReadOnlyDocumentWithoutContent() async throws {
        try await withTempDir { dir in
            let url = dir.appending(path: "latin.txt")
            try Data([0x63, 0x61, 0x66, 0xE9, 0x21]).write(to: url)

            let document = try await CodeFileDocument.open(contentsOf: url, ofType: Self.plainText)
            defer { document.close() }

            #expect(document.readError == .undecodable)
            #expect(document.content == nil)
            #expect(document.isReadOnly)
        }
    }

    @Test
    func openingAFileThatCannotBeReadThrowsWithoutCreatingADocument() async throws {
        try await withTempDir { dir in
            let missing = dir.appending(path: "missing.txt")

            await #expect(throws: CocoaError.self) {
                try await CodeFileDocument.open(contentsOf: missing, ofType: Self.plainText)
            }
        }
    }
}
