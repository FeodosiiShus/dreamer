import AppKit
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
private struct FormattingCommandsHarness {
    let workspace: WorkspaceDocument
    let controller: DreamderWindowController
    let document: CodeFileDocument
    let hosted: HostedSourceEditor
    let textView: TextView
    let fileURL: URL
    let directory: URL

    var diskText: String? {
        try? String(contentsOf: fileURL, encoding: .utf8)
    }

    var markerURL: URL {
        directory.appending(path: "formatter-ran")
    }

    static func makeEmptyWorkspace(in directory: URL) throws -> (WorkspaceDocument, DreamderWindowController) {
        let workspace = WorkspaceDocument()
        try workspace.read(from: directory, ofType: "")
        DreamderDocumentController.shared.addDocument(workspace)
        workspace.makeWindowControllers()
        let controller = try #require(workspace.windowControllers.first as? DreamderWindowController)
        controller.window?.isReleasedWhenClosed = false
        return (workspace, controller)
    }

    static func installPrettier(in directory: URL, script: String) throws {
        let binDirectory = directory.appending(path: "node_modules/.bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        let executable = binDirectory.appending(path: "prettier")
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path(percentEncoded: false)
        )
    }

    static func make(in directory: URL, text: String, prettierScript: String) async throws -> Self {
        let fileURL = directory.appending(path: "app.ts")
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
        try installPrettier(in: directory, script: prettierScript)
        let (workspace, controller) = try makeEmptyWorkspace(in: directory)
        let manager = try #require(workspace.editorManager)
        let file = try #require(workspace.workspaceFileManager?.getFile(
            fileURL.path(percentEncoded: false),
            createIfNotFound: true
        ))
        manager.openTab(item: file)
        let document = try CodeFileDocument(for: fileURL, withContentsOf: fileURL, ofType: "public.plain-text")
        file.fileDocument = document
        let hosted = HostedSourceEditorFixture(
            document: document,
            editorInstance: EditorInstance(workspace: nil, file: file)
        ).host(
            coordinators: [document.contentCoordinator, document.textViewBinder],
            size: NSSize(width: 900, height: 600)
        )
        try await eventually { document.attachedTextView != nil }
        return Self(
            workspace: workspace,
            controller: controller,
            document: document,
            hosted: hosted,
            textView: try #require(document.attachedTextView),
            fileURL: fileURL,
            directory: directory
        )
    }

    func close() {
        hosted.close()
        controller.window?.close()
        workspace.close()
    }
}

@MainActor
@Suite("FormattingCommands", .serialized, .uiGate)
struct FormattingCommandsTests {
    private static let uppercasingPrettier = "#!/bin/sh\n/usr/bin/touch \"$PWD/formatter-ran\"\nexec /usr/bin/tr a-z A-Z\n"
    private static let failingPrettier = "#!/bin/sh\n/usr/bin/touch \"$PWD/formatter-ran\"\necho broken >&2\nexit 1\n"

    private func withFormatOnSave<T>(
        _ enabled: Bool,
        on harness: FormattingCommandsHarness,
        _ body: () async throws -> T
    ) async throws -> T {
        let directory = try makeTemporaryDirectory(label: "FormattingCommandsTests")
        defer { removeTemporaryDirectory(directory) }
        let store = Dreamder.Settings(baseURL: directory)
        store.preferences.textEditing.formatOnSave = enabled
        harness.controller.settings = store
        harness.controller.formatOnSaveTimeout = .seconds(120)
        return try await body()
    }

    @Test
    func reformatCodeFormatsTheSelectedFileWithTheWorkspacePrettier() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingCommandsHarness.make(
                in: directory,
                text: "let  x\n",
                prettierScript: Self.uppercasingPrettier
            )
            defer { harness.close() }

            harness.controller.reformatCode(nil)

            try await eventually { harness.textView.string == "LET  X\n" }
            #expect(FileManager.default.fileExists(atPath: harness.markerURL.path(percentEncoded: false)))
        }
    }

    @Test
    func optimizeImportsWithoutAServerLeavesTheTextAlone() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingCommandsHarness.make(
                in: directory,
                text: "import b\nimport a\n",
                prettierScript: Self.uppercasingPrettier
            )
            defer { harness.close() }

            harness.controller.optimizeImports(nil)
            try await Task.sleep(for: .milliseconds(300))

            #expect(harness.textView.string == "import b\nimport a\n")
        }
    }

    @Test
    func actionsWithoutASelectedFileDoNothing() async throws {
        try await withTempDir { directory in
            let (workspace, controller) = try FormattingCommandsHarness.makeEmptyWorkspace(in: directory)
            defer {
                controller.window?.close()
                workspace.close()
            }

            controller.reformatCode(nil)
            controller.optimizeImports(nil)
            try await Task.sleep(for: .milliseconds(100))

            #expect(controller.getSelectedCodeFile() == nil)
        }
    }

    @Test
    func savingWithFormatOnSaveFormatsBeforeWritingTheFile() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingCommandsHarness.make(
                in: directory,
                text: "let  x\n",
                prettierScript: Self.uppercasingPrettier
            )
            defer { harness.close() }

            try await withFormatOnSave(true, on: harness) {
                harness.controller.saveDocument(harness.controller)
                try await eventually { harness.diskText == "LET  X\n" }
            }
            #expect(harness.textView.string == "LET  X\n")
        }
    }

    @Test
    func aFailingFormatterStillSavesTheDocumentAsItIs() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingCommandsHarness.make(
                in: directory,
                text: "let  x\n",
                prettierScript: Self.failingPrettier
            )
            defer { harness.close() }
            harness.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "// edit\n")

            try await withFormatOnSave(true, on: harness) {
                harness.controller.saveDocument(harness.controller)
                try await eventually { harness.diskText == "// edit\nlet  x\n" }
            }
            #expect(FileManager.default.fileExists(atPath: harness.markerURL.path(percentEncoded: false)))
            #expect(harness.textView.string == "// edit\nlet  x\n")
        }
    }

    @Test
    func savingWithoutFormatOnSaveWritesTheFileWithoutRunningAnyFormatter() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingCommandsHarness.make(
                in: directory,
                text: "let  x\n",
                prettierScript: Self.uppercasingPrettier
            )
            defer { harness.close() }
            harness.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "// edit\n")

            try await withFormatOnSave(false, on: harness) {
                harness.controller.saveDocument(harness.controller)
                try await eventually { harness.diskText == "// edit\nlet  x\n" }
            }
            #expect(!FileManager.default.fileExists(atPath: harness.markerURL.path(percentEncoded: false)))
        }
    }

    @Test
    func savingWithoutASelectedFileDoesNothing() async throws {
        try withTempDir { directory in
            let (workspace, controller) = try FormattingCommandsHarness.makeEmptyWorkspace(in: directory)
            defer {
                controller.window?.close()
                workspace.close()
            }

            controller.saveDocument(controller)

            #expect(controller.getSelectedCodeFile() == nil)
        }
    }
}
