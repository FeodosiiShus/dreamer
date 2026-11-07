import AppKit
import SwiftUI

struct MergeTextPane: NSViewRepresentable {
    let content: MergePaneContent
    let revision: Int
    let isEditable: Bool
    let scrollSync: MergeScrollCoordinator
    let paneID: String
    let onChip: (MergePaneChip) -> Void
    let onTextChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(Islands.island)
        scrollView.borderType = .noBorder

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        textView.identifier = NSUserInterfaceItemIdentifier("merge-pane-\(paneID)")
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = true
        textView.backgroundColor = NSColor(Islands.island)
        textView.textContainerInset = NSSize(width: 8, height: 6)
        textView.font = Islands.codeNSFont
        textView.textColor = NSColor(Islands.editorForeground)
        textView.insertionPointColor = NSColor(Islands.foreground)
        textView.linkTextAttributes = [
            .foregroundColor: NSColor(Islands.secondaryForeground)
        ]
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false

        context.coordinator.textView = textView
        context.coordinator.render(content: content, revision: revision, editable: isEditable)
        scrollSync.register(scrollView, id: paneID)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }
        context.coordinator.render(content: content, revision: revision, editable: isEditable)
        scrollSync.register(scrollView, id: paneID)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MergeTextPane
        weak var textView: NSTextView?
        private var renderedRevision = Int.min

        init(parent: MergeTextPane) {
            self.parent = parent
            super.init()
        }

        func render(content: MergePaneContent, revision: Int, editable: Bool) {
            guard revision != renderedRevision else { return }
            renderedRevision = revision
            guard let textView else { return }

            let selection = textView.selectedRange()
            let attributed = MergeTextPaneRenderer.attributedString(for: content, showsGutter: !editable)
            textView.textStorage?.setAttributedString(attributed)

            guard editable else { return }
            let length = (textView.string as NSString).length
            let location = min(selection.location, length)
            textView.setSelectedRange(NSRange(location: location, length: 0))
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let chip = MergeTextPaneRenderer.chip(for: link) else { return false }
            parent.onChip(chip)
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard parent.isEditable, let textView = notification.object as? NSTextView else { return }
            parent.onTextChange(textView.string)
        }
    }
}

enum MergeTextPaneRenderer {
    private static func gutterColumns(for content: MergePaneContent) -> Int {
        max(content.chips.values.map(\.count).max() ?? 0, 2)
    }

    static func attributedString(for content: MergePaneContent, showsGutter: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = Islands.codeNSFont
        let gutterColumns = gutterColumns(for: content)

        for index in content.lines.indices {
            if showsGutter {
                let chips = content.chips[index] ?? []
                for column in 0..<gutterColumns {
                    let chip = column < chips.count ? chips[column] : nil
                    var attributes: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: NSColor(Islands.disabledForeground)
                    ]
                    if let chip {
                        attributes[.link] = link(for: chip)
                    }
                    result.append(NSAttributedString(
                        string: chip?.symbol ?? " ",
                        attributes: attributes
                    ))
                }
                result.append(NSAttributedString(string: " ", attributes: [
                    .font: font,
                    .foregroundColor: NSColor(Islands.editorForeground)
                ]))
            }

            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor(Islands.editorForeground)
            ]
            let style = index < content.styles.count ? content.styles[index] : MergeLineStyle.unchanged
            if let background = background(for: style) {
                attributes[.backgroundColor] = background
            }
            result.append(NSAttributedString(string: content.lines[index], attributes: attributes))

            if index < content.lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: font,
                    .foregroundColor: NSColor(Islands.editorForeground)
                ]))
            }
        }

        return result
    }

    static func chip(for link: Any) -> MergePaneChip? {
        let url: URL?
        if let value = link as? URL {
            url = value
        } else if let value = link as? NSURL {
            url = value as URL
        } else {
            url = nil
        }
        guard let url, url.scheme == "merge-block", let host = url.host,
              let blockID = Int(url.lastPathComponent) else {
            return nil
        }
        switch host {
        case "left":
            return MergePaneChip(kind: .acceptLeft, blockID: blockID)
        case "right":
            return MergePaneChip(kind: .acceptRight, blockID: blockID)
        case "ignore":
            return MergePaneChip(kind: .ignore, blockID: blockID)
        default:
            return nil
        }
    }

    private static func link(for chip: MergePaneChip) -> NSURL {
        let host: String
        switch chip.kind {
        case .acceptLeft: host = "left"
        case .acceptRight: host = "right"
        case .ignore: host = "ignore"
        }
        return NSURL(string: "merge-block://\(host)/\(chip.blockID)") ?? NSURL(fileURLWithPath: "/")
    }

    private static func background(for style: MergeLineStyle) -> NSColor? {
        switch style {
        case .unchanged:
            return nil
        case .changed:
            return NSColor(DiffColors.modified)
        case .inserted, .resolved:
            return NSColor(DiffColors.inserted)
        case .conflict:
            return NSColor(hex: 0x5F3F3F)
        }
    }
}
