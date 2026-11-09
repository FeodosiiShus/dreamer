import AppKit
import CodeEditTextView
import QuickLookUI
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct OpenQuicklyPreviewViewTests {
    private func host(
        _ url: URL,
        in directory: URL,
        loader: @escaping CodeFileDiskLoader.Loader = CodeFileDiskLoader.live,
        synchronousLimit: Int = FileSizeLimit.synchronousOpen
    ) throws -> HostedView {
        let workspace = try HostedViewFixture.makeWorkspace(in: directory)
        return try HostedViewFixture.hostInWorkspace(workspace) {
            OpenQuicklyPreviewView(
                item: CEWorkspaceFile(url: url),
                loader: loader,
                synchronousLimit: synchronousLimit
            )
        }
    }

    @Test
    func textFileIsShownInAReadOnlyEditor() async throws {
        try await withTempDir { directory in
            let url = directory.appending(path: "note.txt")
            try Data("preview me".utf8).write(to: url)

            let hosted = try host(url, in: directory)
            defer { hosted.close() }

            try await eventually(timeout: .seconds(30)) {
                hosted.layout()
                return !hosted.views(of: CodeEditTextView.TextView.self).isEmpty
            }
            #expect(hosted.views(of: QLPreviewView.self).isEmpty)
        }
    }

    @Test
    func binaryFileFallsBackToTheQuickLookPreview() async throws {
        try await withTempDir { directory in
            let url = directory.appending(path: "blob.bin")
            try FileViewsCoverageFixtures.writeBlob(to: url)

            let hosted = try host(url, in: directory)
            defer { hosted.close() }
            try await eventually(timeout: .seconds(30)) {
                hosted.layout()
                return hosted.views(of: QLPreviewView.self).count == 1
            }
            #expect(hosted.views(of: CodeEditTextView.TextView.self).isEmpty)
        }
    }

    @Test
    func unreadableFileShowsTheMissingURLNotice() async throws {
        try await withTempDir { directory in
            let hosted = try host(directory.appending(path: "missing.txt"), in: directory)
            defer { hosted.close() }
            try await hosted.settle()

            #expect(hosted.views(of: QLPreviewView.self).isEmpty)
            #expect(hosted.views(of: CodeEditTextView.TextView.self).isEmpty)
        }
    }

    @Test
    func nothingIsShownWhileTheFileIsStillBeingRead() async throws {
        try await withTempDir { directory in
            let url = directory.appending(path: "slow.txt")
            try Data("slow preview".utf8).write(to: url)
            let gate = PreviewLoaderGate()
            let loader: CodeFileDiskLoader.Loader = { url, type in
                await gate.pass()
                return try await CodeFileDiskLoader.read(from: url, fileTypeName: type)
            }

            let hosted = try host(url, in: directory, loader: loader, synchronousLimit: 0)
            defer { hosted.close() }
            try await eventually(timeout: .seconds(30)) { await gate.hasEntered }
            try await hosted.settle()

            #expect(hosted.views(of: CodeEditTextView.TextView.self).isEmpty)
            #expect(hosted.views(of: QLPreviewView.self).isEmpty)

            await gate.open()
            try await eventually(timeout: .seconds(30)) {
                hosted.layout()
                return !hosted.views(of: CodeEditTextView.TextView.self).isEmpty
            }
        }
    }

    @Test
    func loadingAFileThatCannotBeReadYieldsAnEmptyDocument() async throws {
        try await withTempDir { directory in
            let missing = CEWorkspaceFile(url: directory.appending(path: "missing.txt"))

            let document = await OpenQuicklyPreviewView.loadDocument(of: missing, loader: CodeFileDiskLoader.live)
            defer { document.close() }

            #expect(document.fileURL == nil)
            #expect(document.content == nil)
            #expect(document.utType == nil)
        }
    }

    @Test
    func loadingATextFileYieldsItsDecodedContent() async throws {
        try await withTempDir { directory in
            let url = directory.appending(path: "note.txt")
            try Data("preview me".utf8).write(to: url)

            let document = await OpenQuicklyPreviewView.loadDocument(
                of: CEWorkspaceFile(url: url),
                loader: CodeFileDiskLoader.live
            )
            defer { document.close() }

            #expect(document.content?.string == "preview me")
            #expect(document.fileURL == url)
        }
    }

    @Test
    func aFileWithinTheSynchronousLimitIsReadWhenTheViewIsCreated() throws {
        try withTempDir { directory in
            let url = directory.appending(path: "small.txt")
            try Data("12345".utf8).write(to: url)
            let item = CEWorkspaceFile(url: url)

            let document = try #require(OpenQuicklyPreviewView.synchronousDocument(of: item, limit: 5))
            defer { document.close() }

            #expect(document.content?.string == "12345")
            #expect(OpenQuicklyPreviewView.synchronousDocument(of: item, limit: 4) == nil)
        }
    }

    @Test
    func aMissingFileWithinTheLimitYieldsAnEmptyDocumentWithoutWaiting() throws {
        try withTempDir { directory in
            let item = CEWorkspaceFile(url: directory.appending(path: "missing.txt"))

            let document = try #require(OpenQuicklyPreviewView.synchronousDocument(of: item, limit: 0))
            defer { document.close() }

            #expect(document.content == nil)
            #expect(document.fileURL == nil)
        }
    }
}

private actor PreviewLoaderGate {
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
