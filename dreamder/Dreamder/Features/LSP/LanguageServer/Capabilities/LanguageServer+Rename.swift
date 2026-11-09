//
//  LanguageServer+Rename.swift
//  Dreamder
//
//  Created by Abe Malla on 2/7/24.
//

import LanguageServerProtocol

extension LanguageServer {
    /// Setup and test the validity of a rename operation at a given location
    func requestPrepareRename(for documentURI: String, _ position: Position) async throws -> PrepareRenameResponse {
        await flushPendingEdits(for: documentURI)
        do {
            let params = TextDocumentPositionParams(
                textDocument: TextDocumentIdentifier(uri: documentURI),
                position: position
            )
            return try await lspInstance.prepareRename(params)
        } catch {
            logger.warning("requestPrepareRename: Error \(error)")
            throw error
        }
    }

    /// Ask the server to compute a workspace change so that the client can perform a workspace-wide rename of a symbol
    func requestRename(
        for documentURI: String,
        position: Position,
        newName name: String
    ) async throws -> RenameResponse {
        await flushPendingEdits(for: documentURI)
        do {
            let params = RenameParams(
                textDocument: TextDocumentIdentifier(uri: documentURI),
                position: position,
                newName: name
            )
            return try await lspInstance.rename(params)
        } catch {
            logger.warning("requestRename: Error \(error)")
            throw error
        }
    }
}

nonisolated enum LSPFileRenameOperation: Sendable {
    case will
    case did
}

extension LanguageServer {
    static var renameMethod: String { "textDocument/rename" }
    static var willRenameFilesMethod: String { "workspace/willRenameFiles" }
    static var didRenameFilesMethod: String { "workspace/didRenameFiles" }

    var supportsPrepareRename: Bool {
        if case let .optionB(options)? = serverCapabilities.renameProvider, options.prepareProvider == true {
            return true
        }
        return dynamicCapabilities
            .registerOptions(for: Self.renameMethod, as: RenameOptions.self)
            .contains { $0.prepareProvider == true }
    }

    func fileRenameRegistrations(_ operation: LSPFileRenameOperation) -> [FileOperationRegistrationOptions] {
        let fileOperations = serverCapabilities.workspace?.fileOperations
        switch operation {
        case .will:
            let registered = dynamicCapabilities
                .registerOptions(for: Self.willRenameFilesMethod, as: FileOperationRegistrationOptions.self)
            return (fileOperations?.willRename.map { [$0] } ?? []) + registered
        case .did:
            let registered = dynamicCapabilities
                .registerOptions(for: Self.didRenameFilesMethod, as: FileOperationRegistrationOptions.self)
            return (fileOperations?.didRename.map { [$0] } ?? []) + registered
        }
    }

    func requestWillRenameFiles(_ files: [FileRename]) async throws -> WorkspaceWillRenameFilesResponse {
        await flushPendingEdits(underAny: files.map(\.oldUri))
        do {
            return try await lspInstance.willRenameFiles(RenameFilesParams(files: files))
        } catch {
            logger.warning("requestWillRenameFiles: Error \(error)")
            throw error
        }
    }

    func notifyDidRenameFiles(_ files: [FileRename]) async throws {
        await flushPendingEdits(underAny: files.map(\.oldUri))
        do {
            try await lspInstance.didRenameFiles(RenameFilesParams(files: files))
        } catch {
            logger.warning("notifyDidRenameFiles: Error \(error)")
            throw error
        }
    }

    private func flushPendingEdits(underAny roots: [String]) async {
        for uri in openFiles.uris where roots.contains(where: { uri == $0 || uri.hasPrefix($0 + "/") }) {
            await flushPendingEdits(for: uri)
        }
    }
}
