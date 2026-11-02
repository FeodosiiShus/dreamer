import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageServerProtocol

struct LSPEditorContext {
    let workspace: WorkspaceDocument
    let tab: EditorInstance
    let fileURL: URL
    let documentURI: String
    let position: Position
    let documentText: String
    let lineText: String
    let symbol: String
    let client: LanguageServer<CodeFileDocument>
}

enum LSPEditorContextResult {
    case ready(LSPEditorContext)
    case missingServer
    case unavailable
}

@MainActor
enum LSPEditorContextResolver {
    static func resolve(workspace: WorkspaceDocument?) -> LSPEditorContextResult {
        guard let workspace,
              let tab = workspace.editorManager?.activeEditor.selectedTab,
              let cursor = tab.cursorPositions.first else {
            return .unavailable
        }
        let fileURL = tab.file.url
        guard let lspService = ServiceContainer.resolve(.singleton, LSPService.self),
              let client = lspService.languageClient(forDocument: fileURL) else {
            return .missingServer
        }
        let position = Position(
            line: max(cursor.start.line, 1) - 1,
            character: max(cursor.start.column, 1) - 1
        )
        let text = documentText(for: tab) ?? ""
        let lines = LSPUsagesMapping.lineUnits(in: text)
        let index = position.line
        let line = lines.indices.contains(index) ? String(decoding: lines[index], as: UTF16.self) : ""
        return .ready(LSPEditorContext(
            workspace: workspace,
            tab: tab,
            fileURL: fileURL,
            documentURI: fileURL.lspURI,
            position: position,
            documentText: text,
            lineText: line,
            symbol: LSPUsagesMapping.symbol(inLine: line, character: position.character),
            client: client
        ))
    }

    static func documentText(for tab: EditorInstance) -> String? {
        if let content = tab.file.fileDocument?.content?.string {
            return content
        }
        return try? String(contentsOf: tab.file.url, encoding: .utf8)
    }
}

@MainActor
enum LSPCaretAnchor {
    static func screenRect(in window: NSWindow?) -> NSRect? {
        guard let window, let textView = focusedTextView(in: window) else { return nil }
        let offset = textView.selectionManager.textSelections.first?.range.location
            ?? textView.textStorage.length
        guard let caret = textView.layoutManager.rectForOffset(offset) else { return nil }
        return window.convertToScreen(textView.convert(caret, to: nil))
    }

    private static func focusedTextView(in window: NSWindow) -> TextView? {
        if let textView = window.firstResponder as? TextView {
            return textView
        }
        return firstTextView(in: window.contentView)
    }

    private static func firstTextView(in view: NSView?) -> TextView? {
        guard let view else { return nil }
        if let textView = view as? TextView {
            return textView
        }
        for subview in view.subviews {
            if let textView = firstTextView(in: subview) {
                return textView
            }
        }
        return nil
    }
}
