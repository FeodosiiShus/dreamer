import AppKit

extension NSDocumentController {
    func openInNewEditorWindow(_ file: CEWorkspaceFile) throws {
        let document: CodeFileDocument
        if let existing = file.fileDocument {
            document = existing
        } else {
            document = try CodeFileDocument(
                contentsOf: file.resolvedURL,
                ofType: file.contentType?.identifier ?? ""
            )
            addDocument(document)
            file.fileDocument = document
        }
        if document.windowControllers.isEmpty {
            document.makeWindowControllers()
        }
        document.showWindows()
    }
}
