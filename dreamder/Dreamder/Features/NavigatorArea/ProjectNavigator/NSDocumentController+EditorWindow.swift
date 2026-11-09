import AppKit

extension NSDocumentController {
    func openInNewEditorWindow(
        _ file: CEWorkspaceFile,
        loader: CodeFileDiskLoader.Loader = CodeFileDiskLoader.live
    ) async throws {
        let document = try await codeFileDocument(for: file, loader: loader)
        if document.windowControllers.isEmpty {
            document.makeWindowControllers()
        }
        document.showWindows()
    }

    private func codeFileDocument(
        for file: CEWorkspaceFile,
        loader: CodeFileDiskLoader.Loader
    ) async throws -> CodeFileDocument {
        if let existing = file.fileDocument {
            return existing
        }
        let opened = try await CodeFileDocument.open(
            contentsOf: file.resolvedURL,
            ofType: file.contentType?.identifier ?? "",
            loader: loader
        )
        if let existing = file.fileDocument {
            opened.close()
            return existing
        }
        addDocument(opened)
        file.fileDocument = opened
        return opened
    }
}
