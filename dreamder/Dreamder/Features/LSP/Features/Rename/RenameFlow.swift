import Foundation
import LanguageServerProtocol

struct RenameBackend {
    var supportsPrepare: @MainActor () -> Bool
    var prepare: @MainActor (_ documentURI: String, _ position: Position) async throws -> PrepareRenameResponse
    var rename: @MainActor (_ documentURI: String, _ position: Position, _ newName: String) async throws
        -> RenameResponse
    var apply: @MainActor (_ edit: WorkspaceEdit) async -> ApplyWorkspaceEditResult
    var documentText: @MainActor () -> String?

    static func make<Document: LanguageServerDocument>(
        client: LanguageServer<Document>,
        documentText: @escaping @MainActor () -> String?,
        apply: @escaping @MainActor (_ edit: WorkspaceEdit) async -> ApplyWorkspaceEditResult
    ) -> RenameBackend {
        RenameBackend(
            supportsPrepare: { client.supportsPrepareRename },
            prepare: { documentURI, position in
                try await client.requestPrepareRename(for: documentURI, position)
            },
            rename: { documentURI, position, newName in
                try await client.requestRename(for: documentURI, position: position, newName: newName)
            },
            apply: apply,
            documentText: documentText
        )
    }
}

@MainActor
protocol RenamePresenting: AnyObject {
    func showMessage(_ message: String)
    func requestName(for target: RenameTarget) async -> String?
}

@MainActor
enum RenameFlow {
    static func run(request: RenameRequest, backend: RenameBackend, presenter: any RenamePresenting) async {
        guard let target = await resolveTarget(request: request, backend: backend, presenter: presenter) else {
            return
        }
        guard let newName = await presenter.requestName(for: target) else { return }
        do {
            guard let edit = try await backend.rename(request.documentURI, request.position, newName) else {
                presenter.showMessage(RenameMessages.nothingToRename)
                return
            }
            guard backend.documentText() == request.documentText else {
                presenter.showMessage(RenameMessages.failure(reason: RenameMessages.documentChanged))
                return
            }
            let result = await backend.apply(edit)
            if !result.applied {
                presenter.showMessage(RenameMessages.failure(reason: result.failureReason))
            }
        } catch {
            presenter.showMessage(RenameMessages.failure(error: error))
        }
    }

    private static func resolveTarget(
        request: RenameRequest,
        backend: RenameBackend,
        presenter: any RenamePresenting
    ) async -> RenameTarget? {
        let resolution: RenameTargetResolution
        if backend.supportsPrepare() {
            do {
                let response = try await backend.prepare(request.documentURI, request.position)
                resolution = RenameTargetMapping.resolve(
                    response,
                    documentText: request.documentText,
                    symbol: request.symbol
                )
            } catch {
                presenter.showMessage(RenameMessages.failure(error: error))
                return nil
            }
        } else {
            resolution = RenameTargetMapping.fallback(symbol: request.symbol)
        }
        guard case .target(let target) = resolution else {
            presenter.showMessage(RenameMessages.notRenameable)
            return nil
        }
        return target
    }
}
