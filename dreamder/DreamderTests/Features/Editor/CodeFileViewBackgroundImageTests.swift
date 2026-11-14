import AppKit
import CodeEditSourceEditor
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct CodeFileViewBackgroundImageTests {
    private func editorBackgroundAlpha(in directory: URL, imagePath: String) async throws -> CGFloat {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        defaults.set(imagePath, forKey: Islands.BackgroundImageKey.path)
        let url = directory.appending(path: "Background.txt")
        try "text\n".write(to: url, atomically: true, encoding: .utf8)
        let document = try CodeFileDocument(for: url, withContentsOf: url, ofType: "public.plain-text")
        let editorInstance = EditorInstance(workspace: nil, file: CEWorkspaceFile(url: url))
        let workspace = try HostedViewFixture.makeWorkspace(in: directory)
        defer { workspace.close() }
        let reference = CodeFileViewControllerReference()
        let hosted = try HostedViewFixture.hostInWorkspace(workspace) {
            CodeFileView(editorInstance: editorInstance, codeFile: document, textViewCoordinators: [reference])
                .defaultAppStorage(defaults)
        }
        defer { hosted.close() }
        try await eventually { reference.controller?.textView != nil }
        let controller = try #require(reference.controller)
        return controller.theme.background.alphaComponent
    }

    @Test
    func aConfiguredBackgroundImageMakesTheEditorThemeBackgroundTransparent() async throws {
        try await withTempDir { directory in
            let alpha = try await editorBackgroundAlpha(in: directory, imagePath: "/tmp/dreamder-background.png")

            #expect(alpha == 0)
        }
    }

    @Test
    func withoutABackgroundImageTheEditorKeepsTheThemeBackground() async throws {
        try await withTempDir { directory in
            let alpha = try await editorBackgroundAlpha(in: directory, imagePath: "")

            #expect(alpha > 0)
        }
    }
}
