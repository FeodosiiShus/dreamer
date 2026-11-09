import Foundation
import LanguageServerProtocol

nonisolated enum SignatureHelpProtocol {
    static let method = "textDocument/signatureHelp"
}

nonisolated enum SignatureHelpTriggerKind: Int, Codable, Sendable {
    case invoked = 1
    case triggerCharacter = 2
    case contentChange = 3
}

nonisolated struct SignatureHelpContext: Codable, Equatable, Sendable {
    var triggerKind: SignatureHelpTriggerKind
    var triggerCharacter: String?
    var isRetrigger: Bool
    var activeSignatureHelp: SignatureHelp?

    static func invoked(activeSignatureHelp: SignatureHelp?) -> SignatureHelpContext {
        SignatureHelpContext(
            triggerKind: .invoked,
            triggerCharacter: nil,
            isRetrigger: activeSignatureHelp != nil,
            activeSignatureHelp: activeSignatureHelp
        )
    }

    static func typed(_ character: String, activeSignatureHelp: SignatureHelp?) -> SignatureHelpContext {
        SignatureHelpContext(
            triggerKind: .triggerCharacter,
            triggerCharacter: character,
            isRetrigger: activeSignatureHelp != nil,
            activeSignatureHelp: activeSignatureHelp
        )
    }

    static func contentChange(activeSignatureHelp: SignatureHelp?) -> SignatureHelpContext {
        SignatureHelpContext(
            triggerKind: .contentChange,
            triggerCharacter: nil,
            isRetrigger: activeSignatureHelp != nil,
            activeSignatureHelp: activeSignatureHelp
        )
    }
}

nonisolated struct SignatureHelpRequestParams: Codable, Equatable, Sendable {
    let textDocument: TextDocumentIdentifier
    let position: Position
    let context: SignatureHelpContext

    func lspAny() throws -> LSPAny {
        try JSONDecoder().decode(LSPAny.self, from: JSONEncoder().encode(self))
    }
}

nonisolated struct SignatureHelpDocumentation: Equatable, Sendable {
    let text: String
    let isMarkdown: Bool

    init?(_ documentation: TwoTypeOption<String, MarkupContent>?) {
        switch documentation {
        case .optionA(let text)?:
            self.init(text: text, isMarkdown: false)
        case .optionB(let content)?:
            self.init(text: content.value, isMarkdown: content.kind == .markdown)
        case nil:
            return nil
        }
    }

    private init?(text: String, isMarkdown: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.text = trimmed
        self.isMarkdown = isMarkdown
    }
}

nonisolated struct SignatureHelpSegment: Equatable, Sendable {
    let text: String
    let isActiveParameter: Bool
}

nonisolated struct SignatureHelpRow: Equatable, Sendable {
    let segments: [SignatureHelpSegment]
    let activeParameterIndex: Int
    let documentation: SignatureHelpDocumentation?
    let parameterDocumentation: SignatureHelpDocumentation?

    var label: String {
        segments.map(\.text).joined()
    }

    init(signature: SignatureInformation, outerActiveParameter: Int?) {
        let parameterIndex = SignatureHelpLabelRanges.activeParameterIndex(
            of: signature,
            outerActiveParameter: outerActiveParameter
        )
        let ranges = SignatureHelpLabelRanges.parameterRanges(of: signature)
        let highlight = ranges.indices.contains(parameterIndex) ? ranges[parameterIndex] : nil
        let parameters = signature.parameters ?? []
        let parameter = parameters.indices.contains(parameterIndex) ? parameters[parameterIndex] : nil
        self.segments = SignatureHelpLabelRanges.segments(label: signature.label, highlight: highlight)
        self.activeParameterIndex = parameterIndex
        self.documentation = SignatureHelpDocumentation(signature.documentation)
        self.parameterDocumentation = SignatureHelpDocumentation(parameter?.documentation)
    }
}

nonisolated enum SignatureHelpLabelRanges {
    static func activeParameterIndex(of signature: SignatureInformation, outerActiveParameter: Int?) -> Int {
        let parameterCount = signature.parameters?.count ?? 0
        guard parameterCount > 0 else { return -1 }
        if let own = signature.activeParameter {
            guard let index = Int(exactly: own), index < parameterCount else { return -1 }
            return index
        }
        guard let outerActiveParameter else { return -1 }
        return (0..<parameterCount).contains(outerActiveParameter) ? outerActiveParameter : 0
    }

    static func parameterRanges(of signature: SignatureInformation) -> [Range<Int>?] {
        let label = Array(signature.label.utf16)
        var searchFrom = 0
        var ranges: [Range<Int>?] = []
        for parameter in signature.parameters ?? [] {
            let range = parameterRange(parameter.label, in: label, searchFrom: searchFrom)
            if let range {
                searchFrom = range.upperBound
            }
            ranges.append(range)
        }
        return ranges
    }

    static func segments(label: String, highlight: Range<Int>?) -> [SignatureHelpSegment] {
        let units = Array(label.utf16)
        guard !units.isEmpty else { return [] }
        guard let highlight, !highlight.isEmpty else {
            return [SignatureHelpSegment(text: label, isActiveParameter: false)]
        }
        let pieces: [(range: Range<Int>, isActive: Bool)] = [
            (0..<highlight.lowerBound, false),
            (highlight, true),
            (highlight.upperBound..<units.count, false)
        ]
        return pieces.filter { !$0.range.isEmpty }.map { piece in
            SignatureHelpSegment(
                text: String(decoding: units[piece.range], as: UTF16.self),
                isActiveParameter: piece.isActive
            )
        }
    }

    private static func parameterRange(
        _ label: TwoTypeOption<String, [UInt]>,
        in signatureLabel: [UInt16],
        searchFrom: Int
    ) -> Range<Int>? {
        switch label {
        case .optionA(let text):
            let needle = Array(text.utf16)
            guard !needle.isEmpty,
                  let start = firstIndex(of: needle, in: signatureLabel, from: searchFrom)
                    ?? firstIndex(of: needle, in: signatureLabel, from: 0) else {
                return nil
            }
            return start..<(start + needle.count)
        case .optionB(let offsets):
            guard offsets.count == 2,
                  let start = Int(exactly: offsets[0]),
                  let end = Int(exactly: offsets[1]),
                  start <= end,
                  end <= signatureLabel.count else {
                return nil
            }
            return start..<end
        }
    }

    private static func firstIndex(of needle: [UInt16], in haystack: [UInt16], from start: Int) -> Int? {
        var index = start
        while index + needle.count <= haystack.count {
            if haystack[index..<(index + needle.count)].elementsEqual(needle) {
                return index
            }
            index += 1
        }
        return nil
    }
}

nonisolated struct SignatureHelpPresentation: Equatable, Sendable {
    let help: SignatureHelp
    let rows: [SignatureHelpRow]
    let activeIndex: Int

    init?(help: SignatureHelp) {
        guard !help.signatures.isEmpty else { return nil }
        let rows = help.signatures.map {
            SignatureHelpRow(signature: $0, outerActiveParameter: help.activeParameter)
        }
        let requested = help.activeSignature ?? 0
        self.init(help: help, rows: rows, activeIndex: rows.indices.contains(requested) ? requested : 0)
    }

    private init(help: SignatureHelp, rows: [SignatureHelpRow], activeIndex: Int) {
        self.help = help
        self.rows = rows
        self.activeIndex = activeIndex
    }

    var activeSignatureHelp: SignatureHelp {
        SignatureHelp(signatures: help.signatures, activeSignature: activeIndex, activeParameter: help.activeParameter)
    }

    func cycled(by step: Int) -> SignatureHelpPresentation {
        let count = rows.count
        let next = ((activeIndex + step) % count + count) % count
        return SignatureHelpPresentation(help: help, rows: rows, activeIndex: next)
    }
}
