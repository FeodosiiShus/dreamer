import AppKit
import CodeEditLanguages
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private struct MarkdownHostedEditorView: View {
    let storage: NSTextStorage
    let theme: Theme
    let providers: [any HighlightProviding]
    let coordinators: [any TextViewCoordinator]
    @State private var state = SourceEditorState()

    var body: some View {
        SourceEditor(
            storage,
            language: .markdown,
            configuration: SourceEditorConfiguration(
                appearance: .init(
                    theme: theme.editor.editorTheme,
                    font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    wrapLines: true
                )
            ),
            state: $state,
            highlightProviders: providers,
            coordinators: coordinators
        )
    }
}

@MainActor
private final class MarkdownHostedSession {
    let window: NSWindow
    let theme: Theme
    private let controllerReference: CodeFileViewControllerReference

    init(text: String, theme: Theme) {
        let reference = CodeFileViewControllerReference()
        self.theme = theme
        self.controllerReference = reference
        let hosting = NSHostingView(
            rootView: MarkdownHostedEditorView(
                storage: CodeTextStorage(string: text),
                theme: theme,
                providers: [MarkdownHighlightProvider()],
                coordinators: [reference]
            )
        )
        hosting.sizingOptions = []
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 900, height: 600)),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFront(nil)
    }

    var textView: TextView? {
        controllerReference.controller?.textView
    }

    func color(at offset: Int) -> NSColor? {
        guard let storage = textView?.textStorage, offset < storage.length else { return nil }
        return storage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor
    }

    func close() {
        window.close()
    }
}

@MainActor
@Suite(.serialized)
struct MarkdownHighlightIntegrationTests {
    private func activeTheme() throws -> Theme {
        try #require(ThemeModel.shared.selectedTheme ?? ThemeModel.shared.themes.first)
    }

    private func sameColor(_ lhs: NSColor?, _ rhs: NSColor) -> Bool {
        guard let lhs = lhs?.usingColorSpace(.sRGB), let rhs = rhs.usingColorSpace(.sRGB) else { return false }
        return abs(lhs.redComponent - rhs.redComponent) < 0.003
            && abs(lhs.greenComponent - rhs.greenComponent) < 0.003
            && abs(lhs.blueComponent - rhs.blueComponent) < 0.003
    }

    private func awaitCondition(
        timeout: Duration = .seconds(20),
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(condition(), sourceLocation: sourceLocation)
    }

    private func offset(of fragment: String, in text: String) -> Int {
        (text as NSString).range(of: fragment).location
    }

    @Test func headerMarkerHeaderTextAndCodeSpanGetTheMappedThemeColors() async throws {
        let text = "# Title `code`\n\n> quoted\n\n- item\n"
        let theme = try activeTheme()
        let session = MarkdownHostedSession(text: text, theme: theme)
        defer { session.close() }
        let keywords = theme.editor.keywords.nsColor
        let variables = theme.editor.variables.nsColor
        let strings = theme.editor.strings.nsColor
        let comments = theme.editor.comments.nsColor
        let plain = theme.editor.text.nsColor

        try await awaitCondition { sameColor(session.color(at: 0), keywords) }

        let title = offset(of: "Title", in: text)
        let backtick = offset(of: "`code`", in: text)
        let code = offset(of: "code", in: text)
        let quoteMarker = offset(of: ">", in: text)
        let quoted = offset(of: "quoted", in: text)
        let listMarker = offset(of: "- item", in: text)

        try await awaitCondition { sameColor(session.color(at: code), strings) }
        try await awaitCondition { sameColor(session.color(at: title), variables) }
        try await awaitCondition { sameColor(session.color(at: backtick), keywords) }
        try await awaitCondition { sameColor(session.color(at: quoteMarker), comments) }
        try await awaitCondition { sameColor(session.color(at: quoted), plain) }
        try await awaitCondition { sameColor(session.color(at: listMarker), keywords) }

        let markerColor = session.color(at: 0)
        let headerColor = session.color(at: title)
        let codeColor = session.color(at: code)
        #expect(markerColor != headerColor)
        #expect(headerColor != codeColor)
        #expect(markerColor != codeColor)
    }

    @Test func typingAnUnderlineRecolorsThePreviousLineAsHeader() async throws {
        let theme = try activeTheme()
        let session = MarkdownHostedSession(text: "Plain", theme: theme)
        defer { session.close() }
        try await awaitCondition { session.textView != nil }
        let textView = try #require(session.textView)
        try await awaitCondition { sameColor(session.color(at: 0), theme.editor.text.nsColor) }

        textView.replaceCharacters(in: NSRange(location: 5, length: 0), with: "\n=====")

        try await awaitCondition { sameColor(session.color(at: 0), theme.editor.variables.nsColor) }
        try await awaitCondition { sameColor(session.color(at: 6), theme.editor.keywords.nsColor) }
    }

    @Test func documentsAboveTheSynchronousLexLimitAreHighlightedAsynchronously() async throws {
        let theme = try activeTheme()
        let text = String(repeating: "# Header\n\n", count: 6_000)
        #expect(text.utf16.count > MarkdownHighlightProvider.synchronousLexLimit)
        let session = MarkdownHostedSession(text: text, theme: theme)
        defer { session.close() }

        try await awaitCondition { sameColor(session.color(at: 0), theme.editor.keywords.nsColor) }
        #expect(sameColor(session.color(at: 2), theme.editor.variables.nsColor))
    }
}
