import AppKit
import CodeEditLanguages
import CodeEditSourceEditor
import CodeEditTextView
import OSLog
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized)
struct EditorDecorationLayoutStabilityTests {
    private struct Fixture {
        let document: CodeFileDocument
        let editorInstance: EditorInstance
    }

    private struct HostedEditor {
        let window: NSWindow
        let hosting: NSHostingView<DecoratedEditor>
    }

    private struct DecoratedEditor: View {
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

    private func loopSignatures(since start: Date) throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(
            at: store.position(date: start),
            matching: NSPredicate(format: "subsystem == %@", "com.apple.AppKit")
        )
        return entries.compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
            .filter {
                $0.contains("has continued for")
                    || $0.contains("Update Constraints in Window passes")
                    || $0.contains("Layout Window passes")
            }
    }

    private func makeFixture(in directory: URL) throws -> Fixture {
        let url = directory.appending(path: "Decorated.swift")
        let source = (0..<1_500).map { "    let value\($0) = \($0) // long trailing comment to exceed the pane width" }
            .joined(separator: "\n")
        try "struct Outer {\n\(source)\n}\n".write(to: url, atomically: true, encoding: .utf8)
        let document = try CodeFileDocument(for: url, withContentsOf: url, ofType: "public.swift-source")
        let instance = EditorInstance(workspace: nil, file: CEWorkspaceFile(url: url))
        return Fixture(document: document, editorInstance: instance)
    }

    private func productionCoordinators(for fixture: Fixture) -> [TextViewCoordinator] {
        [
            fixture.editorInstance.rangeTranslator,
            fixture.document.contentCoordinator,
            fixture.document.languageServerObjects.textCoordinator,
            GitBlameCoordinator(editorInstance: fixture.editorInstance, codeFile: fixture.document),
            EditorContextMenuCoordinator(editorInstance: fixture.editorInstance, codeFile: fixture.document),
            GitGutterCoordinator(codeFile: fixture.document),
            DiagnosticHighlightCoordinator(codeFile: fixture.document),
            InlayHintCoordinator(codeFile: fixture.document),
            IndentGuideCoordinator(),
            EditorBackgroundCoordinator()
        ]
    }

    private func host(_ fixture: Fixture) -> HostedEditor {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(
            rootView: DecoratedEditor(document: fixture.document, coordinators: productionCoordinators(for: fixture))
        )
        hosting.sizingOptions = []
        window.contentView = hosting
        window.orderFront(nil)
        return HostedEditor(window: window, hosting: hosting)
    }

    private func decorationViews(in view: NSView) -> [NSView] {
        var found: [NSView] = []
        if view is IndentGuideOverlayView || view is GitGutterMarkerView
            || view is GitBlameAnnotationView || view is GitBlameInlineView {
            found.append(view)
        }
        for subview in view.subviews {
            found.append(contentsOf: decorationViews(in: subview))
        }
        return found
    }

    @Test
    func editorWithEveryDecorationStaysStableWhileShrinking() async throws {
        try await withTempDir { directory in
            let start = Date()
            let fixture = try makeFixture(in: directory)
            let hosted = host(fixture)
            defer { hosted.window.close() }
            try await Task.sleep(for: .milliseconds(1_500))
            for width in [1100.0, 800.0, 500.0] {
                hosted.window.setContentSize(NSSize(width: width, height: 700))
                try await Task.sleep(for: .milliseconds(1_500))
                let signatures = try loopSignatures(since: start)
                #expect(signatures.isEmpty, "layout loop at width \(width): \(signatures.first ?? "")")
            }
        }
    }

    @Test
    func decorationViewsStayOutsideAutoLayout() async throws {
        try await withTempDir { directory in
            let fixture = try makeFixture(in: directory)
            let hosted = host(fixture)
            defer { hosted.window.close() }
            try await Task.sleep(for: .milliseconds(1_500))
            let decorations = decorationViews(in: hosted.hosting)
            #expect(decorations.contains { $0 is IndentGuideOverlayView })
            #expect(decorations.contains { $0 is GitGutterMarkerView })
            #expect(decorations.contains { $0 is GitBlameAnnotationView })
            for view in decorations {
                #expect(view.translatesAutoresizingMaskIntoConstraints == false, "\(type(of: view))")
                #expect(view.autoresizingMask.isEmpty, "\(type(of: view))")
                #expect(view.constraints.isEmpty, "\(type(of: view))")
            }
        }
    }
}
