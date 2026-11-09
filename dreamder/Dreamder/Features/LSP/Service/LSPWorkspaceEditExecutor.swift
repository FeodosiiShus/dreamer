import Foundation
import LanguageServerProtocol

nonisolated struct LSPWorkspaceEditExecutor: Sendable {
    typealias OpenDocumentEditor = @Sendable (_ edits: [LSPOpenDocumentEdit]) async -> [LSPOpenDocumentOutcome]
    typealias TrashHandler = @Sendable (_ url: URL) throws -> URL?

    var workspaceRoot: URL
    var trashItem: TrashHandler
    var editOpenDocuments: OpenDocumentEditor

    private var fileManager: FileManager {
        .default
    }

    init(
        workspaceRoot: URL,
        trashItem: @escaping TrashHandler = LSPWorkspaceEditExecutor.trashWithFileManager,
        editOpenDocuments: @escaping OpenDocumentEditor = { edits in edits.map { _ in .notOpen } }
    ) {
        self.workspaceRoot = workspaceRoot
        self.trashItem = trashItem
        self.editOpenDocuments = editOpenDocuments
    }

    static let trashWithFileManager: TrashHandler = { url in
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }

    @concurrent
    func apply(_ edit: WorkspaceEdit) async -> ApplyWorkspaceEditResult {
        let operations = LSPWorkspaceEditPlan.operations(for: edit)
        for (index, operation) in operations.enumerated() {
            do {
                try validateFileOperation(operation)
            } catch {
                return Self.failure(error, at: index)
            }
        }
        let requests = operations.enumerated().compactMap { index, operation -> LSPOpenDocumentEdit? in
            guard case let .editText(uri, edits, version) = operation else { return nil }
            return LSPOpenDocumentEdit(index: index, uri: uri, edits: edits, version: version)
        }
        var handled = Set<Int>()
        let outcomes = await editOpenDocuments(requests)
        for (request, outcome) in zip(requests, outcomes) {
            switch outcome {
            case .handled:
                handled.insert(request.index)
            case .notOpen:
                continue
            case let .failed(error):
                return Self.failure(error, at: request.index)
            }
        }
        for (index, operation) in operations.enumerated() where !handled.contains(index) {
            do {
                try perform(operation)
            } catch {
                return Self.failure(error, at: index)
            }
        }
        return ApplyWorkspaceEditResult(applied: true)
    }

    private static func failure(_ error: any Error, at index: Int) -> ApplyWorkspaceEditResult {
        ApplyWorkspaceEditResult(applied: false, failureReason: error.localizedDescription, failedChange: UInt(index))
    }

    private func validateFileOperation(_ operation: LSPWorkspaceEditOperation) throws {
        switch operation {
        case .editText:
            return
        case let .createFile(uri, _, _):
            _ = try confinedURL(uri)
        case let .renameFile(oldURI, newURI, _, _):
            _ = try confinedURL(oldURI)
            _ = try confinedURL(newURI)
        case let .deleteFile(uri, _, _):
            _ = try confinedURL(uri)
        }
    }

    private func perform(_ operation: LSPWorkspaceEditOperation) throws {
        switch operation {
        case let .editText(uri, edits, _):
            try editFile(uri: uri, edits: edits)
        case let .createFile(uri, overwrite, ignoreIfExists):
            try createFile(uri: uri, overwrite: overwrite, ignoreIfExists: ignoreIfExists)
        case let .renameFile(oldURI, newURI, overwrite, ignoreIfExists):
            try renameFile(oldURI: oldURI, newURI: newURI, overwrite: overwrite, ignoreIfExists: ignoreIfExists)
        case let .deleteFile(uri, recursive, ignoreIfNotExists):
            try deleteFile(uri: uri, recursive: recursive, ignoreIfNotExists: ignoreIfNotExists)
        }
    }

    private static func fileURL(_ uri: String) throws -> URL {
        guard let url = LSPFileURI.fileURL(from: uri) else {
            throw LSPWorkspaceEditError.unsupportedURI(uri)
        }
        return url
    }

    private func confinedURL(_ uri: String) throws -> URL {
        let url = try Self.fileURL(uri)
        let rootComponents = resolvedPathComponents(of: workspaceRoot)
        let targetComponents = resolvedPathComponents(of: url)
        guard targetComponents.count > rootComponents.count, targetComponents.starts(with: rootComponents) else {
            throw LSPWorkspaceEditError.outsideWorkspace(uri)
        }
        return url
    }

    private func resolvedPathComponents(of url: URL) -> [String] {
        var existing = url.standardizedFileURL
        var missing: [String] = []
        while (try? fileManager.attributesOfItem(atPath: existing.path)) == nil {
            missing.append(existing.lastPathComponent)
            existing = existing.deletingLastPathComponent()
        }
        return (existing.resolvingSymlinksInPath().path as NSString).pathComponents + missing.reversed()
    }

    private func moveToTrash(_ url: URL) throws {
        _ = try trashItem(url)
    }

    private func editFile(uri: String, edits: [TextEdit]) throws {
        let url = try Self.fileURL(uri)
        guard fileManager.fileExists(atPath: url.path) else {
            throw LSPWorkspaceEditError.notFound(uri)
        }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw LSPWorkspaceEditError.undecodableText(uri)
        }
        let updated = try LSPTextEditApplier.apply(edits, to: text)
        try Data(updated.utf8).write(to: url, options: .atomic)
    }

    private func createFile(uri: String, overwrite: Bool, ignoreIfExists: Bool) throws {
        let url = try confinedURL(uri)
        if fileManager.fileExists(atPath: url.path) {
            if overwrite {
                try moveToTrash(url)
            } else if ignoreIfExists {
                return
            } else {
                throw LSPWorkspaceEditError.alreadyExists(uri)
            }
        }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard fileManager.createFile(atPath: url.path, contents: Data()) else {
            throw LSPWorkspaceEditError.creationFailed(uri)
        }
    }

    private func renameFile(oldURI: String, newURI: String, overwrite: Bool, ignoreIfExists: Bool) throws {
        let source = try confinedURL(oldURI)
        let destination = try confinedURL(newURI)
        guard fileManager.fileExists(atPath: source.path) else {
            throw LSPWorkspaceEditError.notFound(oldURI)
        }
        if fileManager.fileExists(atPath: destination.path) {
            if overwrite {
                try moveToTrash(destination)
            } else if ignoreIfExists {
                return
            } else {
                throw LSPWorkspaceEditError.alreadyExists(newURI)
            }
        }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: source, to: destination)
    }

    private func deleteFile(uri: String, recursive: Bool, ignoreIfNotExists: Bool) throws {
        let url = try confinedURL(uri)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            if ignoreIfNotExists {
                return
            }
            throw LSPWorkspaceEditError.notFound(uri)
        }
        if isDirectory.boolValue, !recursive {
            let contents = try fileManager.contentsOfDirectory(atPath: url.path)
            if !contents.isEmpty {
                throw LSPWorkspaceEditError.directoryNotEmpty(uri)
            }
        }
        try moveToTrash(url)
    }
}
