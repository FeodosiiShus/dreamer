import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import QuickLookUI
import Testing
@testable import Dreamder

private actor EditorLoadGate {
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

@MainActor
@Suite(.serialized, .uiGate)
struct EditorAreaFileLoadingTests {
    @Test
    func theEditorAppearsOnlyWhenTheContentArrivesAndStartsAtTheRequestedPosition() async throws {
        try await withTempDir { directory in
            let url = directory.appending(path: "large.txt")
            try "hello\nworld\nagain\n".write(to: url, atomically: true, encoding: .utf8)
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            let gate = EditorLoadGate()
            let loader: CodeFileDiskLoader.Loader = { url, fileTypeName in
                await gate.pass()
                return try await CodeFileDiskLoader.read(from: url, fileTypeName: fileTypeName)
            }
            let document = CodeFileDocument.loading(
                contentsOf: url,
                ofType: "public.plain-text",
                loader: loader
            ) { _ in }
            defer { document.close() }
            let instance = EditorInstance(workspace: workspace, file: CEWorkspaceFile(url: url))
            let hosted = try HostedViewFixture.hostInWorkspace(workspace) {
                EditorAreaFileView(editorInstance: instance, codeFile: document)
            }
            defer { hosted.close() }
            try await eventually(timeout: .seconds(20)) { await gate.hasEntered }

            instance.cursorPositions = [CursorPosition(line: 2, column: 3)]
            try await hosted.settle()

            #expect(document.isLoading)
            #expect(hosted.views(of: TextView.self).isEmpty)
            #expect(hosted.views(of: QLPreviewView.self).isEmpty)

            await gate.open()
            try await eventually(timeout: .seconds(30)) {
                hosted.layout()
                return !hosted.views(of: TextView.self).isEmpty
            }
            let textView = try #require(hosted.views(of: TextView.self).first)
            try await eventually(timeout: .seconds(30)) {
                textView.selectionManager.textSelections.first?.range.location == 8
            }
            #expect(textView.string == "hello\nworld\nagain\n")
            #expect(instance.cursorPositions.first?.start.line == 2)
        }
    }
}
