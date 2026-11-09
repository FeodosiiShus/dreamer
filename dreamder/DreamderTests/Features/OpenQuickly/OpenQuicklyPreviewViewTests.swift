import AppKit
import CodeEditTextView
import QuickLookUI
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct OpenQuicklyPreviewViewTests {
    private func host(_ url: URL, in directory: URL) throws -> HostedView {
        let workspace = try HostedViewFixture.makeWorkspace(in: directory)
        return try HostedViewFixture.hostInWorkspace(workspace) {
            OpenQuicklyPreviewView(item: CEWorkspaceFile(url: url))
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
            try await hosted.settle()

            #expect(hosted.views(of: QLPreviewView.self).count == 1)
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
}
