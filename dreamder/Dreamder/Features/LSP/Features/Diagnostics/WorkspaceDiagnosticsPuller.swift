import Foundation

@MainActor
final class WorkspaceDiagnosticsPuller {
    static let shared = WorkspaceDiagnosticsPuller()

    private struct Entry {
        weak var client: LSPService.LanguageServerType?
        var state: WorkspaceDiagnosticsPullState
    }

    private var entries: [LSPService.ClientKey: Entry] = [:]
    private var inFlight: Set<LSPService.ClientKey> = []

    init() {}

    @discardableResult
    func pull(client: LSPService.LanguageServerType, key: LSPService.ClientKey) async -> Bool {
        guard let support = client.workspaceDiagnosticsSupport, inFlight.insert(key).inserted else {
            return false
        }
        defer { inFlight.remove(key) }
        var state = entries[key].flatMap { $0.client === client ? $0.state : nil } ?? WorkspaceDiagnosticsPullState()
        do {
            let report = try await client.requestWorkspaceDiagnostics(state.params(identifier: support.identifier))
            for publication in state.apply(report) {
                LSPDiagnosticsPublisher.publish(
                    publication.diagnostics,
                    forDocument: publication.uri,
                    workspacePath: key.workspacePath
                )
            }
            entries[key] = Entry(client: client, state: state)
            return true
        } catch {
            return false
        }
    }

    func pullAll(service: LSPService, workspace: WorkspaceDocument) async {
        guard let path = workspace.fileURL?.absolutePath else { return }
        for (key, client) in service.languageClients where key.workspacePath == path {
            await pull(client: client, key: key)
        }
    }
}
