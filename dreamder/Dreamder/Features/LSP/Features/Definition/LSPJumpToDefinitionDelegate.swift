import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol
import SwiftUI

final class LSPJumpToDefinitionDelegate<DocumentType: LanguageServerDocument>: JumpToDefinitionDelegate {
    private weak var languageServer: LanguageServer<DocumentType>?
    private var documentURI: String?

    func setUp(server: LanguageServer<DocumentType>, document: DocumentType) {
        languageServer = server
        documentURI = document.languageServerURI
    }

    func reset() {
        languageServer = nil
        documentURI = nil
    }

    func queryLinks(forRange range: NSRange, textView: TextViewController) async -> [JumpToDefinitionLink]? {
        guard let server = languageServer, let documentURI else { return nil }
        let origin = await MainActor.run { () -> (position: Position, symbol: String)? in
            guard let lspRange = textView.textView.lspRangeFrom(nsRange: range) else { return nil }
            let symbol = (textView.textView.string as NSString).substring(with: range)
            return (Position(line: lspRange.start.line, character: lspRange.start.character), symbol)
        }
        guard let origin else { return nil }

        var targets: [LSPDefinitionTarget] = []
        if let definition = try? await server.requestGoToDefinition(for: documentURI, position: origin.position) {
            targets = LSPDefinitionMapping.targets(from: definition)
        }
        if targets.isEmpty,
           let declaration = try? await server.requestGoToDeclaration(for: documentURI, position: origin.position) {
            targets = LSPDefinitionMapping.targets(from: declaration)
        }
        guard !targets.isEmpty else { return nil }
        return targets.map { link(for: $0, symbol: origin.symbol) }
    }

    func openLink(link: JumpToDefinitionLink) {
        guard let url = link.url else { return }
        let target = link.targetRange
        MainActor.assumeIsolated {
            LSPDefinitionNavigator.open(url: url, position: target)
        }
    }

    private func link(for target: LSPDefinitionTarget, symbol: String) -> JumpToDefinitionLink {
        let fileURL = LSPDiagnosticMapping.fileURL(fromDocumentURI: target.uri)
        let isSameDocument = target.uri == documentURI
        return JumpToDefinitionLink(
            url: isSameDocument ? nil : fileURL,
            targetRange: CursorPosition(
                line: Int(target.selectionRange.start.line) + 1,
                column: Int(target.selectionRange.start.character) + 1
            ),
            typeName: symbol,
            sourcePreview: preview(for: target) ?? "",
            documentation: nil,
            image: Image("general/locate"),
            imageColor: .clear
        )
    }

    private func preview(for target: LSPDefinitionTarget) -> String? {
        guard let url = LSPDiagnosticMapping.fileURL(fromDocumentURI: target.uri),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let lines = contents.components(separatedBy: .newlines)
        let line = Int(target.range.start.line)
        guard lines.indices.contains(line) else { return nil }
        return lines[line].trimmingCharacters(in: .whitespaces)
    }
}
