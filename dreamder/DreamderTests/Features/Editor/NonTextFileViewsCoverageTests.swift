import AppKit
import Foundation
import PDFKit
import QuickLookUI
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct NonTextFileViewsCoverageTests {
    private func previewedPath(_ preview: QLPreviewView) -> String? {
        (preview.previewItem as? NSURL)?.path
    }

    @Test
    func anyFilePreviewsTheItemAndTracksUpdatesAndDismantle() async throws {
        try await withTempDir { directory in
            let first = directory.appending(path: "first.bin")
            let second = directory.appending(path: "second.bin")
            try FileViewsCoverageFixtures.writeBlob(to: first)
            try FileViewsCoverageFixtures.writeBlob(to: second)

            let hosted = HostedViewFixture.host { AnyFileView(first) }
            defer { hosted.close() }
            try await hosted.settle()

            let preview = try #require(hosted.views(of: QLPreviewView.self).first)
            #expect(previewedPath(preview) == first.path)

            hosted.hosting.rootView = AnyView(AnyFileView(second))
            try await hosted.settle()
            let updated = try #require(hosted.views(of: QLPreviewView.self).first)
            #expect(previewedPath(updated) == second.path)

            hosted.hosting.rootView = AnyView(Color.clear)
            try await hosted.settle()
            #expect(hosted.views(of: QLPreviewView.self).isEmpty)
        }
    }

    @Test
    func imageFilePreviewsPNGAndJPEGThroughQuickLook() async throws {
        try await withTempDir { directory in
            let png = directory.appending(path: "picture.png")
            let jpeg = directory.appending(path: "picture.jpg")
            try FileViewsCoverageFixtures.writePNG(to: png)
            try FileViewsCoverageFixtures.writeJPEG(to: jpeg)

            for url in [png, jpeg] {
                let hosted = HostedViewFixture.host(size: NSSize(width: 500, height: 400)) { ImageFileView(url) }
                defer { hosted.close() }
                try await hosted.settle()

                let preview = try #require(hosted.views(of: QLPreviewView.self).first)
                #expect(previewedPath(preview) == url.path)
            }
        }
    }

    @Test
    func imageLargerThanTheViewIsClampedToTheViewSize() async throws {
        try await withTempDir { directory in
            let large = directory.appending(path: "large.png")
            try FileViewsCoverageFixtures.writePNG(to: large, width: 1_600, height: 1_200)

            let hosted = HostedViewFixture.host(size: NSSize(width: 400, height: 300)) { ImageFileView(large) }
            defer { hosted.close() }
            try await hosted.settle()

            let preview = try #require(hosted.views(of: QLPreviewView.self).first)
            #expect(preview.frame.width <= 400)
            #expect(preview.frame.height <= 300)
        }
    }

    @Test
    func unreadableImageShowsTheFallbackText() async throws {
        try await withTempDir { directory in
            let broken = directory.appending(path: "broken.png")
            try FileViewsCoverageFixtures.writeGarbage(to: broken)

            let hosted = HostedViewFixture.host { ImageFileView(broken) }
            defer { hosted.close() }
            try await hosted.settle()

            #expect(hosted.views(of: QLPreviewView.self).isEmpty)
        }
    }

    @Test
    func missingImageShowsTheFallbackText() async throws {
        try await withTempDir { directory in
            let hosted = HostedViewFixture.host { ImageFileView(directory.appending(path: "missing.png")) }
            defer { hosted.close() }
            try await hosted.settle()

            #expect(hosted.views(of: QLPreviewView.self).isEmpty)
        }
    }

    @Test
    func pdfFileAttachesTheDocumentAndUpdatesOnNewURL() async throws {
        try await withTempDir { directory in
            let one = directory.appending(path: "one.pdf")
            let two = directory.appending(path: "two.pdf")
            let broken = directory.appending(path: "broken.pdf")
            try FileViewsCoverageFixtures.writePDF(to: one, pages: 1)
            try FileViewsCoverageFixtures.writePDF(to: two, pages: 2)
            try FileViewsCoverageFixtures.writeGarbage(to: broken)

            let hosted = HostedViewFixture.host { PDFFileView(one) }
            defer { hosted.close() }
            try await hosted.settle()

            let pdfView = try #require(hosted.views(of: PDFView.self).first)
            #expect(pdfView.document?.pageCount == 1)
            #expect(pdfView.document?.documentURL?.path == one.path)

            hosted.hosting.rootView = AnyView(PDFFileView(two))
            try await hosted.settle()
            #expect(pdfView.document?.pageCount == 2)
            #expect(pdfView.document?.documentURL?.path == two.path)

            hosted.hosting.rootView = AnyView(PDFFileView(broken))
            try await hosted.settle()
            #expect(pdfView.document?.documentURL?.path == two.path)
        }
    }

    @Test
    func unreadablePDFLeavesTheViewWithoutDocument() async throws {
        try await withTempDir { directory in
            let broken = directory.appending(path: "broken.pdf")
            try FileViewsCoverageFixtures.writeGarbage(to: broken)

            let hosted = HostedViewFixture.host { PDFFileView(broken) }
            defer { hosted.close() }
            try await hosted.settle()

            let pdfView = try #require(hosted.views(of: PDFView.self).first)
            #expect(pdfView.document == nil)
        }
    }

    @Test
    func nonTextViewRoutesImagesToTheImagePreview() async throws {
        try await withTempDir { directory in
            let png = directory.appending(path: "picture.png")
            let jpeg = directory.appending(path: "picture.jpg")
            try FileViewsCoverageFixtures.writePNG(to: png)
            try FileViewsCoverageFixtures.writeJPEG(to: jpeg)

            for (url, type) in [(png, FileViewsCoverageFixtures.pngType), (jpeg, FileViewsCoverageFixtures.jpegType)] {
                let document = try FileViewsCoverageFixtures.nonTextDocument(at: url, type: type)
                let hosted = HostedViewFixture.host { NonTextFileView(fileDocument: document) }
                defer { hosted.close() }
                try await hosted.settle()

                let preview = try #require(hosted.views(of: QLPreviewView.self).first)
                #expect(previewedPath(preview) == url.path)
                #expect(hosted.views(of: PDFView.self).isEmpty)
            }
        }
    }

    @Test
    func nonTextViewRoutesPDFsToThePDFView() async throws {
        try await withTempDir { directory in
            let pdf = directory.appending(path: "doc.pdf")
            try FileViewsCoverageFixtures.writePDF(to: pdf)
            let document = try FileViewsCoverageFixtures.nonTextDocument(
                at: pdf,
                type: FileViewsCoverageFixtures.pdfType
            )

            let hosted = HostedViewFixture.host { NonTextFileView(fileDocument: document) }
            defer { hosted.close() }
            try await hosted.settle()

            let pdfView = try #require(hosted.views(of: PDFView.self).first)
            #expect(pdfView.document?.pageCount == 1)
            #expect(hosted.views(of: QLPreviewView.self).isEmpty)
        }
    }

    @Test
    func nonTextViewRoutesOtherTypesToQuickLook() async throws {
        try await withTempDir { directory in
            let blob = directory.appending(path: "blob.bin")
            try FileViewsCoverageFixtures.writeBlob(to: blob)
            let document = try FileViewsCoverageFixtures.nonTextDocument(
                at: blob,
                type: FileViewsCoverageFixtures.dataType
            )

            let hosted = HostedViewFixture.host { NonTextFileView(fileDocument: document) }
            defer { hosted.close() }
            try await hosted.settle()

            let preview = try #require(hosted.views(of: QLPreviewView.self).first)
            #expect(previewedPath(preview) == blob.path)
            #expect(hosted.views(of: PDFView.self).isEmpty)
        }
    }

    @Test
    func nonTextViewFallsBackToQuickLookWhenTheTypeIsUnknown() async throws {
        try await withTempDir { directory in
            let blob = directory.appending(path: "blob.unknownkind")
            try FileViewsCoverageFixtures.writeBlob(to: blob)
            let document = CodeFileDocument()
            document.fileURL = blob
            #expect(document.utType == nil)

            let hosted = HostedViewFixture.host { NonTextFileView(fileDocument: document) }
            defer { hosted.close() }
            try await hosted.settle()

            let preview = try #require(hosted.views(of: QLPreviewView.self).first)
            #expect(previewedPath(preview) == blob.path)
        }
    }

    @Test
    func nonTextViewExplainsAMissingFileURL() async throws {
        let document = CodeFileDocument()
        #expect(document.fileURL == nil)

        let hosted = HostedViewFixture.host { NonTextFileView(fileDocument: document) }
        defer { hosted.close() }
        try await hosted.settle()

        #expect(hosted.views(of: QLPreviewView.self).isEmpty)
        #expect(hosted.views(of: PDFView.self).isEmpty)
    }
}
