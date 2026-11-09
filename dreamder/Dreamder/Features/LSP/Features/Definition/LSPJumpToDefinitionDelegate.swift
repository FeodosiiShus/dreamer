import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol
import SwiftUI

nonisolated struct LSPLinkKey: Hashable, Sendable {
    let fileURL: URL
    let line: Int
    let column: Int
}

nonisolated enum LSPDefinitionPreview {
    static func line(at index: Int, in contents: String) -> String? {
        let lines = contents.components(separatedBy: .newlines)
        guard lines.indices.contains(index) else { return nil }
        return lines[index].trimmingCharacters(in: .whitespaces)
    }

    @concurrent
    static func line(at index: Int, in url: URL) async -> String {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return line(at: index, in: contents) ?? ""
    }
}

@MainActor
enum LSPDefinitionWindowLookup {
    static func windowController(of view: NSView) -> DreamderWindowController? {
        view.window?.windowController as? DreamderWindowController
    }

    static func showUsages(in controller: DreamderWindowController) {
        ShowUsagesController.present(in: controller)
    }
}

final class LSPJumpToDefinitionDelegate<DocumentType: LanguageServerDocument>: JumpToDefinitionDelegate {
    private weak var languageServer: LanguageServer<DocumentType>?
    private var documentURI: String?
    private var documentURL: URL?
    private(set) weak var capturedController: DreamderWindowController?
    private var selfLinkKey: LSPLinkKey?
    private let controllerProvider: @MainActor (NSView) -> DreamderWindowController?
    private let showUsages: @MainActor (DreamderWindowController) -> Void

    init(
        controllerProvider: @escaping @MainActor (NSView) -> DreamderWindowController? =
            LSPDefinitionWindowLookup.windowController(of:),
        showUsages: @escaping @MainActor (DreamderWindowController) -> Void = LSPDefinitionWindowLookup.showUsages(in:)
    ) {
        self.controllerProvider = controllerProvider
        self.showUsages = showUsages
    }

    func setUp(server: LanguageServer<DocumentType>, document: DocumentType) {
        languageServer = server
        documentURI = document.languageServerURI
        documentURL = document.languageServerURI.flatMap { LSPDiagnosticMapping.fileURL(fromDocumentURI: $0) }
    }

    func reset() {
        languageServer = nil
        documentURI = nil
        documentURL = nil
        capturedController = nil
        selfLinkKey = nil
    }

    func attach(to view: NSView) {
        capturedController = controllerProvider(view)
    }

    func rememberSelfLink(_ destination: LSPNavigationDestination?) {
        selfLinkKey = destination.map { LSPLinkKey(fileURL: $0.fileURL, line: $0.line, column: $0.column) }
    }

    func queryLinks(forRange range: NSRange, textView: TextViewController) async -> [JumpToDefinitionLink]? {
        guard let server = languageServer, let documentURI, let documentURL else { return nil }
        let origin = await MainActor.run { () -> (position: Position, symbol: String)? in
            guard let lspRange = textView.textView.lspRangeFrom(nsRange: range) else { return nil }
            let symbol = (textView.textView.string as NSString).substring(with: range)
            return (Position(line: lspRange.start.line, character: lspRange.start.character), symbol)
        }
        guard let origin else { return nil }

        selfLinkKey = nil
        attach(to: textView.view)
        let targets = await server.navigationTargets(for: .declaration, uri: documentURI, position: origin.position)
        let destinations = LSPNavigationPlanner.destinations(from: targets)
        guard !destinations.isEmpty else { return nil }

        let navigationOrigin = LSPNavigationOrigin(fileURL: documentURL, position: origin.position)
        let selfDestination = LSPNavigationPlanner.selfDestination(in: destinations, origin: navigationOrigin)
        rememberSelfLink(selfDestination)

        let linked = selfDestination.map { [$0] } ?? destinations
        var links: [JumpToDefinitionLink] = []
        for destination in linked {
            links.append(await link(for: destination, symbol: origin.symbol))
        }
        return links
    }

    func openLink(link: JumpToDefinitionLink) {
        guard let url = link.url else { return }
        let target = link.targetRange
        MainActor.assumeIsolated {
            let key = LSPLinkKey(fileURL: url, line: target.start.line, column: target.start.column)
            if key == selfLinkKey, let controller = capturedController {
                showUsages(controller)
                return
            }
            LSPDefinitionNavigator.jump(url: url, position: target)
        }
    }

    private func link(for destination: LSPNavigationDestination, symbol: String) async -> JumpToDefinitionLink {
        let preview = await LSPDefinitionPreview.line(at: destination.range.start.line, in: destination.fileURL)
        return JumpToDefinitionLink(
            url: destination.fileURL,
            targetRange: CursorPosition(line: destination.line, column: destination.column),
            typeName: symbol,
            sourcePreview: preview,
            documentation: nil,
            image: Image("general/locate"),
            imageColor: .clear
        )
    }
}
