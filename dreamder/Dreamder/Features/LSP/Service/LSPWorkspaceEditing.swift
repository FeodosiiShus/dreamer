import Foundation
import LanguageServerProtocol

nonisolated enum LSPFileURI {
    static func fileURL(from uri: String) -> URL? {
        if let url = URL(string: uri), url.isFileURL {
            return url
        }
        let prefix = "file://"
        guard uri.hasPrefix(prefix) else { return nil }
        return URL(fileURLWithPath: String(uri.dropFirst(prefix.count)))
    }
}

nonisolated enum LSPWorkspaceEditError: Error, Equatable, LocalizedError {
    case lineOutOfRange(line: Int, lineCount: Int)
    case invalidRange(LSPRange)
    case overlappingEdits
    case unsupportedURI(String)
    case undecodableText(String)
    case alreadyExists(String)
    case notFound(String)
    case directoryNotEmpty(String)
    case creationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .lineOutOfRange(line, lineCount):
            return "Line \(line) is outside the document (\(lineCount) lines)"
        case let .invalidRange(range):
            return "Range \(range) ends before it starts"
        case .overlappingEdits:
            return "Text edits overlap"
        case let .unsupportedURI(uri):
            return "Unsupported document URI: \(uri)"
        case let .undecodableText(uri):
            return "The file cannot be decoded as UTF-8: \(uri)"
        case let .alreadyExists(uri):
            return "The file already exists: \(uri)"
        case let .notFound(uri):
            return "The file does not exist: \(uri)"
        case let .directoryNotEmpty(uri):
            return "The directory is not empty: \(uri)"
        case let .creationFailed(uri):
            return "The file could not be created: \(uri)"
        }
    }
}

nonisolated struct LSPResolvedTextEdit: Sendable, Equatable {
    var edit: TextEdit
    var range: NSRange
}

nonisolated enum LSPTextEditApplier {
    private struct LineTable {
        var starts: [Int] = [0]
        var contentEnds: [Int] = []

        init(_ units: [UInt16]) {
            var index = 0
            while index < units.count {
                let unit = units[index]
                if unit == 0x0A {
                    contentEnds.append(index)
                    starts.append(index + 1)
                } else if unit == 0x0D {
                    contentEnds.append(index)
                    if index + 1 < units.count, units[index + 1] == 0x0A {
                        index += 1
                    }
                    starts.append(index + 1)
                }
                index += 1
            }
            contentEnds.append(units.count)
        }

        func offset(of position: Position) throws -> Int {
            guard position.line >= 0, position.line < starts.count else {
                throw LSPWorkspaceEditError.lineOutOfRange(line: position.line, lineCount: starts.count)
            }
            let start = starts[position.line]
            let contentLength = contentEnds[position.line] - start
            return start + min(max(position.character, 0), contentLength)
        }
    }

    static func resolve(_ edits: [TextEdit], in text: String) throws -> [LSPResolvedTextEdit] {
        try resolve(edits, in: Array(text.utf16))
    }

    static func apply(_ edits: [TextEdit], to text: String) throws -> String {
        let units = Array(text.utf16)
        let resolved = try resolve(edits, in: units)
        var result: [UInt16] = []
        result.reserveCapacity(units.count)
        var cursor = 0
        for item in resolved {
            result.append(contentsOf: units[cursor..<item.range.location])
            result.append(contentsOf: item.edit.newText.utf16)
            cursor = NSMaxRange(item.range)
        }
        result.append(contentsOf: units[cursor...])
        return String(decoding: result, as: UTF16.self)
    }

    private static func resolve(_ edits: [TextEdit], in units: [UInt16]) throws -> [LSPResolvedTextEdit] {
        let table = LineTable(units)
        var indexed: [(index: Int, resolved: LSPResolvedTextEdit)] = []
        indexed.reserveCapacity(edits.count)
        for (index, edit) in edits.enumerated() {
            guard edit.range.start <= edit.range.end else {
                throw LSPWorkspaceEditError.invalidRange(edit.range)
            }
            let start = try table.offset(of: edit.range.start)
            let end = try table.offset(of: edit.range.end)
            let range = NSRange(location: start, length: end - start)
            indexed.append((index, LSPResolvedTextEdit(edit: edit, range: range)))
        }
        indexed.sort { lhs, rhs in
            let lhsRange = lhs.resolved.range
            let rhsRange = rhs.resolved.range
            if lhsRange.location != rhsRange.location {
                return lhsRange.location < rhsRange.location
            }
            if (lhsRange.length == 0) != (rhsRange.length == 0) {
                return lhsRange.length == 0
            }
            return lhs.index < rhs.index
        }
        var previousEnd = 0
        for item in indexed {
            guard item.resolved.range.location >= previousEnd else {
                throw LSPWorkspaceEditError.overlappingEdits
            }
            previousEnd = NSMaxRange(item.resolved.range)
        }
        return indexed.map(\.resolved)
    }
}

nonisolated enum LSPWorkspaceEditOperation: Sendable, Equatable {
    case editText(uri: String, edits: [TextEdit])
    case createFile(uri: String, overwrite: Bool, ignoreIfExists: Bool)
    case renameFile(oldURI: String, newURI: String, overwrite: Bool, ignoreIfExists: Bool)
    case deleteFile(uri: String, recursive: Bool, ignoreIfNotExists: Bool)
}

nonisolated enum LSPWorkspaceEditPlan {
    static func operations(for edit: WorkspaceEdit) -> [LSPWorkspaceEditOperation] {
        if let documentChanges = edit.documentChanges {
            return documentChanges.map(operation(for:))
        }
        return (edit.changes ?? [:])
            .sorted { $0.key < $1.key }
            .map { .editText(uri: $0.key, edits: $0.value) }
    }

    private static func operation(for change: WorkspaceEditDocumentChange) -> LSPWorkspaceEditOperation {
        switch change {
        case let .textDocumentEdit(edit):
            return .editText(uri: edit.textDocument.uri, edits: edit.edits)
        case let .createFile(create) where create.kind == "delete":
            return .deleteFile(uri: create.uri, recursive: false, ignoreIfNotExists: false)
        case let .createFile(create):
            return .createFile(
                uri: create.uri,
                overwrite: create.options?.overwrite ?? false,
                ignoreIfExists: create.options?.ignoreIfExists ?? false
            )
        case let .renameFile(rename):
            return .renameFile(
                oldURI: rename.oldUri,
                newURI: rename.newUri,
                overwrite: rename.options.overwrite ?? false,
                ignoreIfExists: rename.options.ignoreIfExists ?? false
            )
        case let .deleteFile(delete):
            return .deleteFile(
                uri: delete.uri,
                recursive: delete.options.recursive ?? false,
                ignoreIfNotExists: delete.options.ignoreIfNotExists ?? false
            )
        }
    }
}

nonisolated struct LSPWorkspaceEditExecutor: Sendable {
    typealias OpenDocumentEditor = @Sendable (_ uri: String, _ edits: [TextEdit]) async throws -> Bool

    var editOpenDocument: OpenDocumentEditor

    init(editOpenDocument: @escaping OpenDocumentEditor = { _, _ in false }) {
        self.editOpenDocument = editOpenDocument
    }

    @concurrent
    func apply(_ edit: WorkspaceEdit) async -> ApplyWorkspaceEditResult {
        let operations = LSPWorkspaceEditPlan.operations(for: edit)
        for (index, operation) in operations.enumerated() {
            do {
                try await perform(operation)
            } catch {
                return ApplyWorkspaceEditResult(
                    applied: false,
                    failureReason: error.localizedDescription,
                    failedChange: UInt(index)
                )
            }
        }
        return ApplyWorkspaceEditResult(applied: true)
    }

    private func perform(_ operation: LSPWorkspaceEditOperation) async throws {
        switch operation {
        case let .editText(uri, edits):
            if try await editOpenDocument(uri, edits) {
                return
            }
            try Self.editFile(uri: uri, edits: edits)
        case let .createFile(uri, overwrite, ignoreIfExists):
            try Self.createFile(uri: uri, overwrite: overwrite, ignoreIfExists: ignoreIfExists)
        case let .renameFile(oldURI, newURI, overwrite, ignoreIfExists):
            try Self.renameFile(oldURI: oldURI, newURI: newURI, overwrite: overwrite, ignoreIfExists: ignoreIfExists)
        case let .deleteFile(uri, recursive, ignoreIfNotExists):
            try Self.deleteFile(uri: uri, recursive: recursive, ignoreIfNotExists: ignoreIfNotExists)
        }
    }

    private static func fileURL(_ uri: String) throws -> URL {
        guard let url = LSPFileURI.fileURL(from: uri) else {
            throw LSPWorkspaceEditError.unsupportedURI(uri)
        }
        return url
    }

    private static func editFile(uri: String, edits: [TextEdit]) throws {
        let url = try fileURL(uri)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LSPWorkspaceEditError.notFound(uri)
        }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw LSPWorkspaceEditError.undecodableText(uri)
        }
        let updated = try LSPTextEditApplier.apply(edits, to: text)
        try Data(updated.utf8).write(to: url, options: .atomic)
    }

    private static func createFile(uri: String, overwrite: Bool, ignoreIfExists: Bool) throws {
        let url = try fileURL(uri)
        let manager = FileManager.default
        if manager.fileExists(atPath: url.path) {
            if overwrite {
                try manager.removeItem(at: url)
            } else if ignoreIfExists {
                return
            } else {
                throw LSPWorkspaceEditError.alreadyExists(uri)
            }
        }
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard manager.createFile(atPath: url.path, contents: Data()) else {
            throw LSPWorkspaceEditError.creationFailed(uri)
        }
    }

    private static func renameFile(oldURI: String, newURI: String, overwrite: Bool, ignoreIfExists: Bool) throws {
        let source = try fileURL(oldURI)
        let destination = try fileURL(newURI)
        let manager = FileManager.default
        guard manager.fileExists(atPath: source.path) else {
            throw LSPWorkspaceEditError.notFound(oldURI)
        }
        if manager.fileExists(atPath: destination.path) {
            if overwrite {
                try manager.removeItem(at: destination)
            } else if ignoreIfExists {
                return
            } else {
                throw LSPWorkspaceEditError.alreadyExists(newURI)
            }
        }
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.moveItem(at: source, to: destination)
    }

    private static func deleteFile(uri: String, recursive: Bool, ignoreIfNotExists: Bool) throws {
        let url = try fileURL(uri)
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            if ignoreIfNotExists {
                return
            }
            throw LSPWorkspaceEditError.notFound(uri)
        }
        if isDirectory.boolValue, !recursive {
            let contents = try manager.contentsOfDirectory(atPath: url.path)
            if !contents.isEmpty {
                throw LSPWorkspaceEditError.directoryNotEmpty(uri)
            }
        }
        try manager.removeItem(at: url)
    }
}

nonisolated enum LSPShowDocumentPlan: Sendable, Equatable {
    case external(URL)
    case editor(URL, selection: LSPRange?, takeFocus: Bool)
    case invalid

    private static let externalSchemes: Set<String> = ["http", "https", "mailto"]

    static func make(for params: ShowDocumentParams) -> LSPShowDocumentPlan {
        if let url = URL(string: params.uri), let scheme = url.scheme?.lowercased(), externalSchemes.contains(scheme) {
            return .external(url)
        }
        guard let fileURL = LSPFileURI.fileURL(from: params.uri) else {
            return .invalid
        }
        if params.external == true {
            return .external(fileURL)
        }
        return .editor(fileURL, selection: params.selection, takeFocus: params.takeFocus ?? true)
    }
}
