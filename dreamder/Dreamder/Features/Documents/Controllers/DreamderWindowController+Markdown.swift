import AppKit
import SwiftUI
import CodeEditSourceEditor
import CodeEditTextView

enum MarkdownEditorPreferences {
    static let emphasisStyleKey = "dreamder.markdown.emphasisStyle"
    static let tableStyleKey = "dreamder.markdown.tableStyle"

    static func emphasisStyle(defaults: UserDefaults = .standard) -> MarkdownEmphasisStyle {
        defaults.string(forKey: emphasisStyleKey) == "underscores" ? .underscores : .asterisks
    }

    static func tableStyle(defaults: UserDefaults = .standard) -> MarkdownTableStyle {
        switch defaults.string(forKey: tableStyleKey) {
        case "compact": .compact
        case "tight": .tight
        default: .aligned
        }
    }
}

struct MarkdownEditorTarget {
    let editorInstance: EditorInstance
    let codeFile: CodeFileDocument
    let storage: NSTextStorage
    let textView: TextView?

    var text: String { storage.string }

    var selections: [NSRange] {
        if let textView {
            let ranges = textView.selectionManager.textSelections.map(\.range)
            if !ranges.isEmpty { return ranges }
        }
        return Self.ranges(of: editorInstance.cursorPositions, in: text)
    }

    var caretOffset: Int {
        if let first = textView?.selectionManager.textSelections.first { return first.range.location }
        return Self.resolvedRanges(of: editorInstance.cursorPositions, in: text).first.location
    }

    nonisolated static func ranges(of positions: [CursorPosition], in text: String) -> [NSRange] {
        let resolved = resolvedRanges(of: positions, in: text)
        return [resolved.first] + resolved.others
    }

    nonisolated private static func resolvedRanges(
        of positions: [CursorPosition],
        in text: String
    ) -> (first: NSRange, others: [NSRange]) {
        let lines = MarkdownText(text).lines
        var ranges = positions.compactMap { position -> NSRange? in
            if position.range.location != NSNotFound {
                return position.range
            }
            guard position.start.line > 0, position.start.line <= lines.count else { return nil }
            let line = lines[position.start.line - 1]
            let offset = min(line.start + max(position.start.column - 1, 0), line.contentEnd)
            return NSRange(location: offset, length: 0)
        }
        guard !ranges.isEmpty else { return (NSRange(location: 0, length: 0), []) }
        let first = ranges.removeFirst()
        return (first, ranges)
    }

    func apply(_ result: MarkdownActionResult) {
        if let textView {
            if let edit = result.edit {
                textView.replaceCharacters(in: edit.range, with: edit.replacement)
            }
            textView.selectionManager.setSelectedRanges(result.selections)
            return
        }
        if let edit = result.edit {
            storage.beginEditing()
            storage.replaceCharacters(in: edit.range, with: edit.replacement)
            storage.endEditing()
            codeFile.updateChangeCount(.changeDone)
        }
        editorInstance.cursorPositions = result.selections.map { CursorPosition(range: $0) }
    }
}

extension DreamderWindowController {
    var isActiveEditorMarkdown: Bool {
        MarkdownPreviewLayoutStore.isMarkdownFile(workspace?.editorManager?.activeEditor.selectedTab?.file.url)
    }

    @IBAction func markdownToggleBold(_ sender: Any?) {
        performMarkdownCommand(.toggle(.bold))
    }

    @IBAction func markdownToggleItalic(_ sender: Any?) {
        performMarkdownCommand(.toggle(.italic))
    }

    @IBAction func markdownToggleStrikethrough(_ sender: Any?) {
        performMarkdownCommand(.toggle(.strikethrough))
    }

    @IBAction func markdownToggleCodeSpan(_ sender: Any?) {
        performMarkdownCommand(.toggle(.codeSpan))
    }

    @IBAction func markdownCreateLink(_ sender: Any?) {
        performMarkdownCommand(.createLink)
    }

    @IBAction func markdownHeaderNormal(_ sender: Any?) {
        performMarkdownCommand(.headerLevel(0))
    }

    @IBAction func markdownHeaderTitle(_ sender: Any?) {
        performMarkdownCommand(.headerLevel(1))
    }

    @IBAction func markdownHeaderSubtitle(_ sender: Any?) {
        performMarkdownCommand(.headerLevel(2))
    }

    @IBAction func markdownHeading3(_ sender: Any?) {
        performMarkdownCommand(.headerLevel(3))
    }

    @IBAction func markdownHeading4(_ sender: Any?) {
        performMarkdownCommand(.headerLevel(4))
    }

    @IBAction func markdownHeading5(_ sender: Any?) {
        performMarkdownCommand(.headerLevel(5))
    }

    @IBAction func markdownHeading6(_ sender: Any?) {
        performMarkdownCommand(.headerLevel(6))
    }

    @IBAction func markdownHeaderUp(_ sender: Any?) {
        performMarkdownCommand(.headerUp)
    }

    @IBAction func markdownHeaderDown(_ sender: Any?) {
        performMarkdownCommand(.headerDown)
    }

    @IBAction func markdownFormatTable(_ sender: Any?) {
        performMarkdownCommand(.formatTable)
    }

    @IBAction func markdownGenerateTableOfContents(_ sender: Any?) {
        performMarkdownCommand(.generateTableOfContents)
    }

    @IBAction func markdownInsertTable(_ sender: Any?) {
        guard let target = markdownEditorTarget() else { return }
        MarkdownTablePopoverPresenter.shared.present(for: target, in: window) { [weak self] contentRows, columns in
            self?.performMarkdownCommand(.insertTable(contentRows: contentRows, columns: columns))
        }
    }

    @discardableResult
    func performMarkdownCommand(_ command: MarkdownEditorCommand) -> Bool {
        guard let target = markdownEditorTarget() else { return false }
        let result = MarkdownEditorCommandRunner.run(
            command,
            text: target.text,
            selections: target.selections,
            environment: markdownEnvironment(for: target)
        )
        guard let result else { return false }
        target.apply(result)
        return true
    }

    func markdownEditorTarget() -> MarkdownEditorTarget? {
        guard let editorInstance = workspace?.editorManager?.activeEditor.selectedTab,
              MarkdownPreviewLayoutStore.isMarkdownFile(editorInstance.file.url),
              let codeFile = editorInstance.file.fileDocument,
              let storage = codeFile.content else { return nil }
        var textView: TextView?
        if let focused = window?.firstResponder as? TextView, focused.textStorage === storage {
            textView = focused
        }
        return MarkdownEditorTarget(
            editorInstance: editorInstance,
            codeFile: codeFile,
            storage: storage,
            textView: textView
        )
    }

    private func markdownEnvironment(for target: MarkdownEditorTarget) -> MarkdownEditorEnvironment {
        var environment = MarkdownEditorEnvironment()
        environment.emphasisStyle = MarkdownEditorPreferences.emphasisStyle()
        environment.tableStyle = MarkdownEditorPreferences.tableStyle()
        environment.tabSize = target.codeFile.effectiveTabWidth
        let indentOption = target.codeFile.effectiveIndentOption
        if indentOption.indentType == .spaces {
            environment.indentSize = max(indentOption.spaceCount, 1)
        }
        environment.clipboard = markdownClipboard
        let directory = target.editorInstance.file.url.deletingLastPathComponent()
        environment.relativePathExists = { path in
            FileManager.default.fileExists(atPath: directory.appending(path: path).path(percentEncoded: false))
        }
        return environment
    }
}

final class MarkdownTablePopoverPresenter {
    static let shared = MarkdownTablePopoverPresenter()

    private(set) var popover: NSPopover?

    func present(
        for target: MarkdownEditorTarget,
        in window: NSWindow?,
        onSelect: @escaping (_ contentRows: Int, _ columns: Int) -> Void
    ) {
        popover?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MarkdownTableGridPicker { [weak self] contentRows, columns in
                self?.dismiss()
                onSelect(contentRows, columns)
            }
        )
        self.popover = popover
        if let textView = target.textView {
            let rect = textView.layoutManager.rectForOffset(target.caretOffset) ?? textView.visibleRect
            popover.show(relativeTo: rect, of: textView, preferredEdge: .maxY)
        } else if let contentView = window?.contentView {
            popover.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .maxY)
        } else {
            self.popover = nil
        }
    }

    private func dismiss() {
        popover?.close()
        popover = nil
    }
}
