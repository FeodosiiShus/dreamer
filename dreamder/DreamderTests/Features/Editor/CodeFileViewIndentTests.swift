import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct CodeFileViewIndentTests {
    private typealias IndentOption = SettingsData.TextEditingSettings.IndentOption

    @MainActor
    private struct Harness {
        let workspace: WorkspaceDocument
        let document: CodeFileDocument
        let hosted: HostedView
        let reference: CodeFileViewControllerReference

        var controller: TextViewController? {
            reference.controller
        }

        func close() {
            hosted.close()
            workspace.close()
        }
    }

    private func open(
        in directory: URL,
        name: String,
        data: Data,
        editorConfig: String = "",
        type: String = "public.plain-text",
        expectsEditor: Bool = true,
        global: GlobalIndent = GlobalIndent(style: .spaces, spaceCount: 4, tabWidth: 4)
    ) async throws -> Harness {
        try "root = true\n\(editorConfig)".write(
            to: directory.appending(path: ".editorconfig"),
            atomically: true,
            encoding: .utf8
        )
        let url = directory.appending(path: name)
        try data.write(to: url)
        let document = try CodeFileDocument(for: url, withContentsOf: url, ofType: type)
        document.globalIndentOverride = global
        let editorInstance = EditorInstance(workspace: nil, file: CEWorkspaceFile(url: url))
        let workspace = try HostedViewFixture.makeWorkspace(in: directory)
        let reference = CodeFileViewControllerReference()
        let hosted = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 900, height: 600)) {
            CodeFileView(editorInstance: editorInstance, codeFile: document, textViewCoordinators: [reference])
        }
        if expectsEditor {
            try await eventually { reference.controller?.textView != nil }
        } else {
            try await hosted.settle()
        }
        return Harness(workspace: workspace, document: document, hosted: hosted, reference: reference)
    }

    private func open(
        in directory: URL,
        name: String,
        text: String,
        editorConfig: String = "",
        global: GlobalIndent = GlobalIndent(style: .spaces, spaceCount: 4, tabWidth: 4)
    ) async throws -> Harness {
        try await open(
            in: directory,
            name: name,
            data: Data(text.utf8),
            editorConfig: editorConfig,
            global: global
        )
    }

    @Test
    func editorConfigBeatsDetectionAndTheGlobalSetting() async throws {
        try await withTempDir { dir in
            let harness = try await open(
                in: dir,
                name: "a.txt",
                text: "a {\n  b\n  c\n}\n",
                editorConfig: "[*.txt]\nindent_style = tab\ntab_width = 3\n",
                global: GlobalIndent(style: .spaces, spaceCount: 5, tabWidth: 6)
            )
            defer { harness.close() }
            let controller = try #require(harness.controller)

            #expect(controller.indentOption == .tab)
            #expect(controller.tabWidth == 3)
            #expect(harness.document.resolvedIndent.styleSource == .editorConfig)
        }
    }

    @Test
    func detectionBeatsTheLanguageDefaultAndTheGlobalSetting() async throws {
        try await withTempDir { dir in
            let harness = try await open(
                in: dir,
                name: "tool.py",
                text: "def f():\n  return 1\n  pass\n",
                global: GlobalIndent(style: .tab, spaceCount: 5, tabWidth: 6)
            )
            defer { harness.close() }
            let controller = try #require(harness.controller)

            #expect(controller.indentOption == .spaces(count: 2))
            #expect(controller.tabWidth == 6)
            #expect(harness.document.resolvedIndent.styleSource == .detected)
        }
    }

    @Test
    func theLanguageDefaultBeatsTheGlobalSetting() async throws {
        try await withTempDir { dir in
            let python = try await open(
                in: dir,
                name: "tool.py",
                text: "x = 1\n",
                global: GlobalIndent(style: .tab, spaceCount: 5, tabWidth: 6)
            )
            defer { python.close() }

            #expect(python.controller?.indentOption == .spaces(count: 4))
            #expect(python.document.resolvedIndent.styleSource == .languageDefault)
        }
        try await withTempDir { dir in
            let golang = try await open(
                in: dir,
                name: "main.go",
                text: "package main\n",
                global: GlobalIndent(style: .spaces, spaceCount: 3, tabWidth: 6)
            )
            defer { golang.close() }

            #expect(golang.controller?.indentOption == .tab)
            #expect(golang.document.resolvedIndent.styleSource == .languageDefault)
        }
    }

    @Test
    func theGlobalSettingIsTheLastResort() async throws {
        try await withTempDir { dir in
            let harness = try await open(
                in: dir,
                name: "plain.txt",
                text: "x = 1\n",
                global: GlobalIndent(style: .spaces, spaceCount: 5, tabWidth: 6)
            )
            defer { harness.close() }
            let controller = try #require(harness.controller)

            #expect(controller.indentOption == .spaces(count: 5))
            #expect(controller.tabWidth == 6)
            #expect(harness.document.resolvedIndent.styleSource == .global)
        }
    }

    @Test
    func aDocumentOverrideBeatsEverythingAndUpdatesTheLiveEditor() async throws {
        try await withTempDir { dir in
            let harness = try await open(
                in: dir,
                name: "a.txt",
                text: "a {\n  b\n  c\n}\n",
                editorConfig: "[*.txt]\nindent_style = tab\ntab_width = 3\n",
                global: GlobalIndent(style: .spaces, spaceCount: 5, tabWidth: 6)
            )
            defer { harness.close() }
            let controller = try #require(harness.controller)
            #expect(controller.indentOption == .tab)

            harness.document.indentOption = IndentOption(indentType: .spaces, spaceCount: 7)
            harness.document.defaultTabWidth = 5

            try await eventually { controller.indentOption == .spaces(count: 7) && controller.tabWidth == 5 }
            #expect(harness.document.resolvedIndent.styleSource == .documentOverride)
        }
    }

    @Test
    func normalFilesAreEditableAndHighlighted() async throws {
        try await withTempDir { dir in
            let harness = try await open(in: dir, name: "plain.txt", text: "x = 1\n")
            defer { harness.close() }
            let controller = try #require(harness.controller)

            #expect(controller.isEditable)
            #expect(!controller.highlightProviders.isEmpty)
            #expect(harness.document.notice == nil)
        }
    }

    @Test
    func binaryFilesAreReadOnlyWithoutHighlightingAndShowABanner() async throws {
        try await withTempDir { dir in
            let harness = try await open(
                in: dir,
                name: "blob.bin",
                data: Data([0x61, 0x62, 0x00, 0x63, 0x64]),
                type: "public.data"
            )
            defer { harness.close() }
            let controller = try #require(harness.controller)

            #expect(!controller.isEditable)
            #expect(controller.highlightProviders.isEmpty)
            #expect(controller.textView.string == "ab\u{2400}cd")
            #expect(harness.document.notice == .binary)
            #expect(harness.hosted.renders())
        }
    }

    @Test
    func undecodableFilesShowTheReadErrorInsteadOfAnEditor() async throws {
        try await withTempDir { dir in
            let harness = try await open(
                in: dir,
                name: "latin.txt",
                data: Data([0x63, 0x61, 0x66, 0xE9, 0x21]),
                expectsEditor: false
            )
            defer { harness.close() }
            let blank = HostedViewFixture.host(size: NSSize(width: 900, height: 600)) { Color.clear }
            defer { blank.close() }
            try await blank.settle()

            #expect(harness.document.readError == .undecodable)
            #expect(harness.controller == nil)
            #expect(harness.hosted.renders())
            #expect(HostedView.pixelsDiffer(harness.hosted.snapshot(), blank.snapshot()))
        }
    }

    @Test
    func noticeBannersAndErrorViewsRender() async throws {
        let notices: [CodeFileNotice] = [
            .binary,
            .tooLarge(byteCount: FileSizeLimit.intelligence),
            .readError(.undecodable)
        ]
        var snapshots: [NSBitmapImageRep?] = []
        for notice in notices {
            let hosted = HostedViewFixture.host(size: NSSize(width: 600, height: 80)) {
                CodeFileNoticeBanner(notice: notice)
            }
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())
            snapshots.append(hosted.snapshot())
        }
        #expect(HostedView.pixelsDiffer(snapshots[0], snapshots[1]))

        let error = HostedViewFixture.host(size: NSSize(width: 600, height: 200)) {
            CodeFileReadErrorView(error: .undecodable)
        }
        defer { error.close() }
        try await error.settle()
        #expect(error.renders())
    }
}
