import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite("WorkspaceEditApplierDefaults", .serialized, .uiGate)
struct WorkspaceEditApplierLiveTrashTests {
    @Test
    func anApplierBuiltLikeProductionAppliesAnEditThatDoesNotDelete() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory)
            defer { harness.workspace.close() }
            let created = directory.appending(path: "created.txt")
            let creation = try LSPExecutorEdits.create(created.absoluteString)

            let result = await WorkspaceEditApplier(client: harness.client).apply(creation)

            #expect(result.applied)
            #expect(FileManager.default.fileExists(atPath: created.path))
        }
    }
}
