import Foundation

@MainActor
enum LSPUsagesLoader {
    static func rows(for context: LSPEditorContext) async -> [LSPUsageRow] {
        let response = (try? await context.client.requestFindReferences(
            for: context.documentURI,
            context.position,
            true
        )) ?? nil
        let locations = LSPUsagesMapping.locations(from: response)
        guard !locations.isEmpty else { return [] }

        var texts: [String: String] = [context.documentURI: context.documentText]
        let needed = Set(locations.map(\.uri))
        if let tabs = context.workspace.editorManager?.activeEditor.tabs {
            for tab in tabs {
                let uri = tab.file.url.lspURI
                guard needed.contains(uri), texts[uri] == nil else { continue }
                if let content = tab.file.fileDocument?.content?.string {
                    texts[uri] = content
                }
            }
        }
        for uri in needed where texts[uri] == nil {
            guard let url = LSPDiagnosticMapping.fileURL(fromDocumentURI: uri),
                  let text = await readText(at: url) else {
                continue
            }
            texts[uri] = text
        }

        return LSPUsagesMapping.rows(
            from: locations,
            fileTexts: texts,
            workspacePath: context.workspace.fileURL?.absolutePath
        )
    }

    private static func readText(at url: URL) async -> String? {
        await Task.detached(priority: .userInitiated) {
            try? String(contentsOf: url, encoding: .utf8)
        }.value
    }
}
