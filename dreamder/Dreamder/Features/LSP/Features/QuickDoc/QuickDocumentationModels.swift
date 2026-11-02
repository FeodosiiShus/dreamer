import Foundation
import LanguageServerProtocol

struct QuickDocumentationContent: Equatable {
    let text: String
    let isMarkdown: Bool
}

enum QuickDocumentationBlock: Equatable {
    case prose(String)
    case plain(String)
    case code(String)

    var text: String {
        switch self {
        case .prose(let text), .plain(let text), .code(let text):
            return text
        }
    }

    var isCode: Bool {
        if case .code = self { return true }
        return false
    }
}

enum QuickDocumentationMarkup {
    static func content(from response: HoverResponse) -> QuickDocumentationContent? {
        guard let hover = response else { return nil }
        switch hover.contents {
        case .optionA(let marked):
            let text = markedText(marked).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return QuickDocumentationContent(text: text, isMarkdown: true)
        case .optionB(let markedList):
            let parts = markedList
                .map { markedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !parts.isEmpty else { return nil }
            return QuickDocumentationContent(text: parts.joined(separator: "\n\n"), isMarkdown: true)
        case .optionC(let markup):
            let text = markup.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return QuickDocumentationContent(text: text, isMarkdown: markup.kind == .markdown)
        }
    }

    static func markedText(_ marked: MarkedString) -> String {
        switch marked {
        case .optionA(let string):
            return string
        case .optionB(let pair):
            return "```\(pair.language.rawValue)\n\(pair.value)\n```"
        }
    }

    static func blocks(from content: QuickDocumentationContent) -> [QuickDocumentationBlock] {
        guard content.isMarkdown else {
            return [.plain(content.text)]
        }
        return blocks(fromMarkdown: content.text)
    }

    static func blocks(fromMarkdown markdown: String) -> [QuickDocumentationBlock] {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        var blocks: [QuickDocumentationBlock] = []
        var prose: [String] = []
        var code: [String] = []
        var insideFence = false

        func flushProse() {
            let text = prose.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(.prose(text))
            }
            prose.removeAll()
        }

        func flushCode() {
            let text = code.joined(separator: "\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.code(text))
            }
            code.removeAll()
        }

        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("```") {
                if insideFence {
                    flushCode()
                } else {
                    flushProse()
                }
                insideFence.toggle()
                continue
            }
            if insideFence {
                code.append(String(line))
            } else {
                prose.append(String(line))
            }
        }

        if insideFence {
            flushCode()
        } else {
            flushProse()
        }
        return blocks
    }
}
