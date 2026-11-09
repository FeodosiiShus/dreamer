import AppKit
import CodeEditTextView
import Foundation
import PDFKit
import QuickLookUI
import SwiftUI
import Testing
import WebKit
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct EditorAreaFileViewsCoverageTests {
    private func host(
        _ workspace: WorkspaceDocument,
        document: CodeFileDocument,
        url: URL
    ) throws -> HostedView {
        let instance = EditorInstance(workspace: workspace, file: CEWorkspaceFile(url: url))
        return try HostedViewFixture.hostInWorkspace(workspace) {
            EditorAreaFileView(editorInstance: instance, codeFile: document)
        }
    }

    @Test
    func imageDocumentShowsPreviewAndPublishesDimensionsAndSizeThenClearsThemOnDisappear() async throws {
        try await withTempDir { directory in
            let png = directory.appending(path: "picture.png")
            try FileViewsCoverageFixtures.writePNG(to: png, width: 64, height: 48)
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            let statusBar = try #require(workspace.statusBarViewModel)
            let document = try FileViewsCoverageFixtures.nonTextDocument(
                at: png,
                type: FileViewsCoverageFixtures.pngType
            )

            let hosted = try host(workspace, document: document, url: png)
            defer { hosted.close() }
            try await hosted.settle()

            #expect(hosted.views(of: QLPreviewView.self).count == 1)
            try await eventually { statusBar.dimensions != nil }
            #expect(statusBar.dimensions?.width == 64)
            #expect(statusBar.dimensions?.height == 48)
            let expectedSize = try FileViewsCoverageFixtures.fileSize(of: png)
            #expect(statusBar.fileSize == expectedSize)

            hosted.hosting.rootView = AnyView(Color.clear)
            try await hosted.settle()
            #expect(statusBar.dimensions == nil)
            #expect(statusBar.fileSize == nil)
        }
    }

    @Test
    func binaryDocumentPublishesFileSizeWithoutDimensions() async throws {
        try await withTempDir { directory in
            let blob = directory.appending(path: "blob.bin")
            try FileViewsCoverageFixtures.writeBlob(to: blob)
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            let statusBar = try #require(workspace.statusBarViewModel)
            let document = try FileViewsCoverageFixtures.nonTextDocument(
                at: blob,
                type: FileViewsCoverageFixtures.dataType
            )

            let hosted = try host(workspace, document: document, url: blob)
            defer { hosted.close() }
            try await hosted.settle()

            #expect(hosted.views(of: QLPreviewView.self).count == 1)
            try await eventually { statusBar.fileSize != nil }
            let expectedSize = try FileViewsCoverageFixtures.fileSize(of: blob)
            #expect(statusBar.fileSize == expectedSize)
            #expect(statusBar.dimensions == nil)
        }
    }

    @Test
    func pdfDocumentShowsThePDFViewAndPublishesItsFileSize() async throws {
        try await withTempDir { directory in
            let pdf = directory.appending(path: "doc.pdf")
            try FileViewsCoverageFixtures.writePDF(to: pdf)
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            let statusBar = try #require(workspace.statusBarViewModel)
            let document = try FileViewsCoverageFixtures.nonTextDocument(
                at: pdf,
                type: FileViewsCoverageFixtures.pdfType
            )

            let hosted = try host(workspace, document: document, url: pdf)
            defer { hosted.close() }
            try await hosted.settle()

            #expect(hosted.views(of: PDFView.self).count == 1)
            try await eventually { statusBar.fileSize != nil }
            #expect(statusBar.dimensions == nil)
        }
    }

    @Test
    func textDocumentShowsTheCodeEditorWithoutTouchingTheStatusBarInfo() async throws {
        try await withTempDir { directory in
            let url = directory.appending(path: "note.txt")
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            let statusBar = try #require(workspace.statusBarViewModel)
            let document = try FileViewsCoverageFixtures.textDocument(at: url, contents: "hello\nworld\n")

            let hosted = try host(workspace, document: document, url: url)
            defer { hosted.close() }

            try await eventually { !hosted.views(of: TextView.self).isEmpty }
            #expect(hosted.views(of: QLPreviewView.self).isEmpty)
            #expect(statusBar.fileSize == nil)
            #expect(statusBar.dimensions == nil)
        }
    }

    @Test
    func markdownDocumentShowsTheEditorWithPreviewLayout() async throws {
        try await withTempDir { directory in
            let url = directory.appending(path: "note.md")
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            let document = try FileViewsCoverageFixtures.textDocument(
                at: url,
                contents: "# Title\n\nbody\n",
                type: "public.source-code"
            )

            let hosted = try host(workspace, document: document, url: url)
            defer { hosted.close() }

            try await eventually {
                !hosted.views(of: TextView.self).isEmpty || !hosted.views(of: WKWebView.self).isEmpty
            }
            #expect(hosted.views(of: QLPreviewView.self).isEmpty)
        }
    }
}
