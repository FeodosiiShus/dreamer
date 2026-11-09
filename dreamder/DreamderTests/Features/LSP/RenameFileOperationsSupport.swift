import Foundation
import LanguageClient
import LanguageServerProtocol
import Synchronization
import Testing
@testable import Dreamder

final class RenameOrderObservingConnection: ServerConnection, Sendable {
    private let inner: ScriptedServerConnection
    private let old: URL
    private let new: URL
    private let recorded = Mutex<[String]>([])

    init(inner: ScriptedServerConnection, old: URL, new: URL) {
        self.inner = inner
        self.old = old
        self.new = new
    }

    var eventSequence: EventSequence {
        inner.eventSequence
    }

    var observations: [String] {
        recorded.withLock { $0 }
    }

    private func record(_ name: String) {
        let oldState = FileManager.default.fileExists(atPath: old.path) ? "exists" : "missing"
        let newState = FileManager.default.fileExists(atPath: new.path) ? "exists" : "missing"
        recorded.withLock { $0.append("\(name) old=\(oldState) new=\(newState)") }
    }

    func sendNotification(_ notif: ClientNotification) async throws {
        if notif.method == .workspaceDidRenameFiles {
            record("didRenameFiles")
        }
        try await inner.sendNotification(notif)
    }

    func sendRequest<Response: Decodable & Sendable>(_ request: ClientRequest) async throws -> Response {
        if request.method == .workspaceWillRenameFiles {
            record("willRenameFiles")
        }
        return try await inner.sendRequest(request)
    }
}

@MainActor
final class RenameFileOperationsApplier {
    var calls: [(edit: WorkspaceEdit, client: LSPFileOperations.Client)] = []
    var result = ApplyWorkspaceEditResult(applied: true)

    func apply(_ edit: WorkspaceEdit, _ client: LSPFileOperations.Client) async -> ApplyWorkspaceEditResult {
        calls.append((edit, client))
        return result
    }
}
