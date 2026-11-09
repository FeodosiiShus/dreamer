import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct WorkspaceDocumentIndexTests {
    private static let fileNames = ["File 1.txt", "Documentation.docc", "Makefile"]

    private func writeFiles(in directory: URL) throws {
        let folder1 = directory.appending(path: "Folder 2")
        let folder2 = directory.appending(path: "Longer Folder With Some 💯 Special Chars ⁉️")
        try FileManager.default.createDirectory(at: folder1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder2, withIntermediateDirectories: true)
        try "Loren Ipsum".write(to: directory.appending(path: "File 1.txt"), atomically: true, encoding: .utf8)
        try "Aperiam asperiores".write(
            to: folder1.appending(path: "Documentation.docc"),
            atomically: true,
            encoding: .utf8
        )
        try "Loren Ipsum".write(to: folder2.appending(path: "Makefile"), atomically: true, encoding: .utf8)
    }

    @Test
    func addingTheWorkspaceToTheIndexIndexesEveryTextFile() async throws {
        try await withTempDir { directory in
            let workspace = try WorkspaceDocument(for: directory, withContentsOf: directory, ofType: "")
            defer { workspace.close() }
            let searchState = try #require(workspace.searchState)
            try writeFiles(in: directory)

            searchState.addProjectToIndex()

            try await eventually(timeout: .seconds(60)) {
                searchState.indexStatus == .done
                    && Set(searchState.indexer?.documents().map(\.lastPathComponent) ?? []) == Set(Self.fileNames)
            }
        }
    }
}
