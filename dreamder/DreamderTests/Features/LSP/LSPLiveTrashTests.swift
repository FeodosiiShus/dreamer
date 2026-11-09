import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite
struct LSPLiveTrashTests {
    @Test
    func theLiveHandlerMovesAFileToTheTrashAndReportsWhereItWent() throws {
        try withTempDir { directory in
            let name = "dreamder-live-trash-\(UUID().uuidString).txt"
            let file = directory.appending(path: name)
            try "recoverable".write(to: file, atomically: true, encoding: .utf8)

            let trashed = try #require(try LSPWorkspaceEditExecutor.trashWithFileManager(file))
            let removal = Result { try FileManager.default.removeItem(at: trashed) }

            #expect(!FileManager.default.fileExists(atPath: file.path))
            #expect(trashed.lastPathComponent == name)
            #expect(throws: Never.self) { try removal.get() }
        }
    }

    @Test
    func anExecutorBuiltWithDefaultArgumentsAppliesAnEditThatDoesNotDelete() async throws {
        try await withTempDir { directory in
            let created = directory.appending(path: "created.txt")
            let creation = try LSPExecutorEdits.create(created.absoluteString)

            let result = await LSPWorkspaceEditExecutor(workspaceRoot: directory).apply(creation)

            #expect(result.applied)
            #expect(FileManager.default.fileExists(atPath: created.path))
        }
    }
}
