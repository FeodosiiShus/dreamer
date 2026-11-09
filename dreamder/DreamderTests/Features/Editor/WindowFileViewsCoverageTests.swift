import AppKit
import CodeEditTextView
import Foundation
import PDFKit
import QuickLookUI
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct WindowFileViewsCoverageTests {
    @Test
    func textDocumentOpensInTheCodeEditor() async throws {
        try await withTempDir { directory in
            let document = try FileViewsCoverageFixtures.textDocument(
                at: directory.appending(path: "note.txt"),
                contents: "hello\nworld\n"
            )

            let hosted = HostedViewFixture.host { SettingsInjector { WindowCodeFileView(codeFile: document) } }
            defer { hosted.close() }

            try await eventually { !hosted.views(of: TextView.self).isEmpty }
            #expect(hosted.views(of: QLPreviewView.self).isEmpty)
            #expect(hosted.views(of: PDFView.self).isEmpty)
        }
    }

    @Test
    func binaryDocumentOpensInQuickLook() async throws {
        try await withTempDir { directory in
            let blob = directory.appending(path: "blob.bin")
            try FileViewsCoverageFixtures.writeBlob(to: blob)
            let document = try FileViewsCoverageFixtures.nonTextDocument(
                at: blob,
                type: FileViewsCoverageFixtures.dataType
            )

            let hosted = HostedViewFixture.host { SettingsInjector { WindowCodeFileView(codeFile: document) } }
            defer { hosted.close() }
            try await hosted.settle()

            #expect(hosted.views(of: QLPreviewView.self).count == 1)
            #expect(hosted.views(of: TextView.self).isEmpty)
        }
    }

    @Test
    func imageDocumentOpensInQuickLook() async throws {
        try await withTempDir { directory in
            let png = directory.appending(path: "picture.png")
            try FileViewsCoverageFixtures.writePNG(to: png)
            let document = try FileViewsCoverageFixtures.nonTextDocument(
                at: png,
                type: FileViewsCoverageFixtures.pngType
            )

            let hosted = HostedViewFixture.host { SettingsInjector { WindowCodeFileView(codeFile: document) } }
            defer { hosted.close() }
            try await hosted.settle()

            #expect(hosted.views(of: QLPreviewView.self).count == 1)
        }
    }

    @Test
    func pdfDocumentOpensInThePDFView() async throws {
        try await withTempDir { directory in
            let pdf = directory.appending(path: "doc.pdf")
            try FileViewsCoverageFixtures.writePDF(to: pdf)
            let document = try FileViewsCoverageFixtures.nonTextDocument(
                at: pdf,
                type: FileViewsCoverageFixtures.pdfType
            )

            let hosted = HostedViewFixture.host { SettingsInjector { WindowCodeFileView(codeFile: document) } }
            defer { hosted.close() }
            try await hosted.settle()

            let pdfView = try #require(hosted.views(of: PDFView.self).first)
            #expect(pdfView.document?.pageCount == 1)
        }
    }

    @Test
    func documentWithoutURLStillHostsWithoutPreview() async throws {
        let document = CodeFileDocument()

        let hosted = HostedViewFixture.host { SettingsInjector { WindowCodeFileView(codeFile: document) } }
        defer { hosted.close() }
        try await hosted.settle()

        #expect(hosted.views(of: QLPreviewView.self).isEmpty)
        #expect(hosted.views(of: TextView.self).isEmpty)
    }
}
