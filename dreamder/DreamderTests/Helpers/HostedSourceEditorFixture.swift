import AppKit
import CodeEditLanguages
import CodeEditSourceEditor
import CodeEditTextView
import SwiftUI
import Testing
@testable import Dreamder

struct HostedSourceEditorView: View {
    let document: CodeFileDocument
    let coordinators: [TextViewCoordinator]
    @State private var state = SourceEditorState()

    var body: some View {
        let theme = ThemeModel.shared.selectedTheme ?? ThemeModel.shared.themes.first
        if let theme, let content = document.content {
            SourceEditor(
                content,
                language: .swift,
                configuration: SourceEditorConfiguration(
                    appearance: .init(
                        theme: theme.editor.editorTheme,
                        font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                        wrapLines: false
                    )
                ),
                state: $state,
                coordinators: coordinators
            )
        }
    }
}

@MainActor
final class HostedSourceEditor {
    let window: NSWindow
    let hosting: NSHostingView<HostedSourceEditorView>
    let coordinators: [TextViewCoordinator]
    private let controllerReference: CodeFileViewControllerReference

    init(
        window: NSWindow,
        hosting: NSHostingView<HostedSourceEditorView>,
        coordinators: [TextViewCoordinator],
        controllerReference: CodeFileViewControllerReference
    ) {
        self.window = window
        self.hosting = hosting
        self.coordinators = coordinators
        self.controllerReference = controllerReference
    }

    var controller: TextViewController? {
        controllerReference.controller
    }

    func coordinator<Coordinator: TextViewCoordinator>(ofType type: Coordinator.Type) -> Coordinator? {
        coordinators.compactMap { $0 as? Coordinator }.first
    }

    func views<Match: NSView>(ofType type: Match.Type) -> [Match] {
        Self.views(ofType: type, in: hosting)
    }

    func close() {
        window.close()
    }

    private static func views<Match: NSView>(ofType type: Match.Type, in root: NSView) -> [Match] {
        var found: [Match] = []
        if let match = root as? Match {
            found.append(match)
        }
        for subview in root.subviews {
            found.append(contentsOf: views(ofType: type, in: subview))
        }
        return found
    }
}

@MainActor
struct HostedSourceEditorFixture {
    let document: CodeFileDocument
    let editorInstance: EditorInstance

    static func make(
        in directory: URL,
        fileName: String = "Decorated.swift",
        typeIdentifier: String = "public.swift-source",
        contents: String
    ) throws -> Self {
        let url = directory.appending(path: fileName)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        let document = try CodeFileDocument(for: url, withContentsOf: url, ofType: typeIdentifier)
        let instance = EditorInstance(workspace: nil, file: CEWorkspaceFile(url: url))
        return Self(document: document, editorInstance: instance)
    }

    static func makeWide(in directory: URL) throws -> Self {
        let source = (0..<1_500).map { "    let value\($0) = \($0) // long trailing comment to exceed the pane width" }
            .joined(separator: "\n")
        return try make(in: directory, contents: "struct Outer {\n\(source)\n}\n")
    }

    static func registerWorkspace(at directory: URL) throws -> WorkspaceDocument {
        let workspace = WorkspaceDocument()
        try workspace.read(from: directory, ofType: "")
        DreamderDocumentController.shared.addDocument(workspace)
        return workspace
    }

    func productionCoordinators() -> [TextViewCoordinator] {
        [
            editorInstance.rangeTranslator,
            document.contentCoordinator,
            document.languageServerObjects.textCoordinator,
            GitBlameCoordinator(editorInstance: editorInstance, codeFile: document),
            EditorContextMenuCoordinator(editorInstance: editorInstance, codeFile: document),
            GitGutterCoordinator(codeFile: document),
            DiagnosticHighlightCoordinator(codeFile: document),
            InlayHintCoordinator(codeFile: document),
            OnTypeFormattingCoordinator(codeFile: document),
            SelectionRangeCoordinator(editorInstance: editorInstance, codeFile: document),
            FoldingCoordinator(editorInstance: editorInstance, codeFile: document),
            SignatureHelpCoordinator(editorInstance: editorInstance, codeFile: document),
            RecentLocationsCoordinator(editorInstance: editorInstance, codeFile: document),
            IndentGuideCoordinator(),
            EditorBackgroundCoordinator()
        ]
    }

    func host(
        coordinators: [TextViewCoordinator]? = nil,
        size: NSSize = NSSize(width: 1400, height: 900)
    ) -> HostedSourceEditor {
        let controllerReference = CodeFileViewControllerReference()
        let allCoordinators = (coordinators ?? productionCoordinators()) + [controllerReference]
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(
            rootView: HostedSourceEditorView(document: document, coordinators: allCoordinators)
        )
        hosting.sizingOptions = []
        window.contentView = hosting
        window.orderFront(nil)
        return HostedSourceEditor(
            window: window,
            hosting: hosting,
            coordinators: allCoordinators,
            controllerReference: controllerReference
        )
    }
}

@MainActor
extension HostedSourceEditor {
    private static let insetTolerance: CGFloat = 0.01

    var hasSettledGeometry: Bool {
        guard let controller, let textView = controller.textView else { return false }
        window.layoutIfNeeded()
        return gutterInsetIsApplied(controller: controller, textView: textView) && firstLineIsTypeset(in: textView)
    }

    func waitForSettledGeometry() async throws {
        try await eventually { self.hasSettledGeometry }
    }

    private func gutterInsetIsApplied(controller: TextViewController, textView: TextView) -> Bool {
        guard controller.showGutter else { return abs(textView.textInsets.left) < Self.insetTolerance }
        guard let gutter = views(ofType: GutterView.self).first, gutter.frame.width > 0 else { return false }
        return abs(textView.textInsets.left - gutter.frame.width) < Self.insetTolerance
    }

    private func firstLineIsTypeset(in textView: TextView) -> Bool {
        guard textView.textStorage.length > 0 else { return true }
        guard let line = textView.layoutManager.textLineForIndex(0) else { return false }
        return !line.data.lineFragments.isEmpty
    }
}
