import Foundation
import LanguageServerProtocol
import Synchronization
@testable import Dreamder

final class LSPExecutorRecorder<Value: Sendable>: Sendable {
    private let storage = Mutex<[Value]>([])

    func append(_ value: Value) {
        storage.withLock { $0.append(value) }
    }

    var values: [Value] {
        storage.withLock { $0 }
    }
}

struct LSPExecutorFailure: LocalizedError {
    var errorDescription: String? { "refused" }
}

final class LSPTrashRecorder: Sendable {
    let trashDirectory: URL
    let trashed = LSPExecutorRecorder<String>()
    let failure: (any Error)?

    init(trashDirectory: URL, failure: (any Error)? = nil) {
        self.trashDirectory = trashDirectory
        self.failure = failure
    }

    func trash(_ url: URL) throws -> URL? {
        if let failure {
            throw failure
        }
        trashed.append(url.path)
        let destination = trashDirectory.appending(path: UUID().uuidString)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }
}

struct LSPExecutorFixture {
    let base: URL
    let root: URL
    let outside: URL
    let trashRecorder: LSPTrashRecorder

    init(in directory: URL, trashFailure: (any Error)? = nil) throws {
        let trash = directory.appending(path: "trash", directoryHint: .isDirectory)
        base = directory
        root = directory.appending(path: "workspace", directoryHint: .isDirectory)
        outside = directory.appending(path: "outside", directoryHint: .isDirectory)
        for folder in [root, outside, trash] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        trashRecorder = LSPTrashRecorder(trashDirectory: trash, failure: trashFailure)
    }

    var trashed: [String] {
        trashRecorder.trashed.values
    }

    var trashHandler: LSPWorkspaceEditExecutor.TrashHandler {
        let recorder = trashRecorder
        return { url in try recorder.trash(url) }
    }

    func executor(
        edit: @escaping LSPWorkspaceEditExecutor.OpenDocumentEditor = { requests in requests.map { _ in .notOpen } }
    ) -> LSPWorkspaceEditExecutor {
        LSPWorkspaceEditExecutor(workspaceRoot: root, trashItem: trashHandler, editOpenDocuments: edit)
    }

    @discardableResult
    func makeFile(in folder: URL, _ name: String, _ text: String) throws -> URL {
        let url = folder.appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func makeFolder(in parent: URL, _ name: String) throws -> URL {
        let url = parent.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

enum LSPExecutorEdits {
    static func text(_ start: (Int, Int), _ end: (Int, Int), _ text: String) -> TextEdit {
        TextEdit(range: LSPRange(startPair: start, endPair: end), newText: text)
    }

    static func decode(_ json: String) throws -> WorkspaceEdit {
        try JSONDecoder().decode(WorkspaceEdit.self, from: Data(json.utf8))
    }

    static func create(_ uri: String, options: String? = nil) throws -> WorkspaceEdit {
        let options = options.map { #","options":\#($0)"# } ?? ""
        return try decode(#"{"documentChanges":[{"kind":"create","uri":"\#(uri)"\#(options)}]}"#)
    }

    static func rename(_ source: URL, _ target: URL, options: String = "{}") throws -> WorkspaceEdit {
        try decode("""
        {"documentChanges":[{"kind":"rename",
          "oldUri":"\(source.absoluteString)",
          "newUri":"\(target.absoluteString)",
          "options":\(options)}]}
        """)
    }

    static func delete(_ url: URL, recursive: Bool? = nil, ignoreIfNotExists: Bool? = nil) -> WorkspaceEdit {
        WorkspaceEdit(changes: nil, documentChanges: [.deleteFile(DeleteFile(
            kind: "delete",
            uri: url.absoluteString,
            options: DeleteFileOptions(recursive: recursive, ignoreIfNotExists: ignoreIfNotExists)
        ))])
    }

    static func outsideFailure(_ uri: String, at index: UInt = 0) -> ApplyWorkspaceEditResult {
        ApplyWorkspaceEditResult(
            applied: false,
            failureReason: "The file is outside the workspace: \(uri)",
            failedChange: index
        )
    }
}
