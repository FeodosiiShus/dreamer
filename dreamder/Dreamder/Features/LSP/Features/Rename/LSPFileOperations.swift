import Foundation
import LanguageServerProtocol

@MainActor
enum LSPFileOperations {
    typealias Client = LanguageServer<CodeFileDocument>
    typealias EditApplier = @MainActor (_ edit: WorkspaceEdit, _ client: Client) async -> ApplyWorkspaceEditResult

    static func willRename(from oldURL: URL, to newURL: URL) async {
        await willRename(from: oldURL, to: newURL, service: .shared)
    }

    static func didRename(from oldURL: URL, to newURL: URL) async {
        await didRename(from: oldURL, to: newURL, service: .shared)
    }

    static func willRename(from oldURL: URL, to newURL: URL, service: LSPService?) async {
        guard let service else { return }
        await willRename(
            from: oldURL,
            to: newURL,
            clients: Array(service.languageClients.values),
            apply: { edit, client in await service.applyWorkspaceEdit(edit, via: client) }
        )
    }

    static func didRename(from oldURL: URL, to newURL: URL, service: LSPService?) async {
        guard let service else { return }
        await didRename(from: oldURL, to: newURL, clients: Array(service.languageClients.values))
    }

    static func willRename(
        from oldURL: URL,
        to newURL: URL,
        clients: [Client],
        apply: EditApplier
    ) async {
        let files = [FileRename(oldUri: oldURL.lspURI, newUri: newURL.lspURI)]
        for client in registeredClients(.will, for: oldURL, to: newURL, among: clients) {
            do {
                guard let edit = try await client.requestWillRenameFiles(files) else { continue }
                let result = await apply(edit, client)
                if !result.applied {
                    client.logger.warning("willRenameFiles edit was not applied: \(result.failureReason ?? "")")
                }
            } catch {
                client.logger.warning("willRenameFiles failed: \(error)")
            }
        }
    }

    static func didRename(from oldURL: URL, to newURL: URL, clients: [Client]) async {
        let files = [FileRename(oldUri: oldURL.lspURI, newUri: newURL.lspURI)]
        for client in registeredClients(.did, for: oldURL, to: newURL, among: clients) {
            do {
                try await client.notifyDidRenameFiles(files)
            } catch {
                client.logger.warning("didRenameFiles failed: \(error)")
            }
        }
    }

    static func registeredClients(
        _ operation: LSPFileRenameOperation,
        for oldURL: URL,
        to newURL: URL,
        among clients: [Client]
    ) -> [Client] {
        let isFolder = isDirectory(newURL, oldURL)
        let oldURI = oldURL.lspURI
        return clients.filter { client in
            guard contains(root: client.rootPath, url: oldURL) else { return false }
            return client.fileRenameRegistrations(operation).contains {
                LSPFileOperationFilterMatcher.matches(
                    $0,
                    uri: oldURI,
                    isDirectory: isFolder,
                    rootPath: client.rootPath.path(percentEncoded: false)
                )
            }
        }
    }

    static func contains(root: URL, url: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        let path = url.standardizedFileURL.path(percentEncoded: false)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return path == rootPath || path.hasPrefix(prefix)
    }

    static func isDirectory(_ primary: URL, _ fallback: URL) -> Bool {
        for url in [primary, fallback] {
            if let value = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory {
                return value
            }
        }
        return false
    }
}
