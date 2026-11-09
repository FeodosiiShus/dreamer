//
//  OpenQuicklyPreviewView.swift
//  DreamderModules/QuickOpen
//
//  Created by Pavel Kasila on 20.03.22.
//

import SwiftUI

struct OpenQuicklyPreviewView: View {

    private let item: CEWorkspaceFile
    private let loader: CodeFileDiskLoader.Loader

    @State private var editorInstance: EditorInstance
    @State private var document: CodeFileDocument?

    @State private var undoRegistration = UndoManagerRegistration()

    init(
        item: CEWorkspaceFile,
        loader: @escaping CodeFileDiskLoader.Loader = CodeFileDiskLoader.live,
        synchronousLimit: Int = FileSizeLimit.synchronousOpen
    ) {
        self.item = item
        self.loader = loader
        self._editorInstance = State(wrappedValue: EditorInstance(workspace: nil, file: item))
        self._document = State(wrappedValue: Self.synchronousDocument(of: item, limit: synchronousLimit))
    }

    var body: some View {
        Group {
            if let document {
                content(of: document)
            }
        }
        .task(id: item.url) {
            guard document == nil else { return }
            document = await Self.loadDocument(of: item, loader: loader)
        }
    }

    @ViewBuilder
    private func content(of document: CodeFileDocument) -> some View {
        if let utType = document.utType, utType.conforms(to: .text) {
            CodeFileView(editorInstance: editorInstance, codeFile: document, isEditable: false)
                .environment(undoRegistration)
        } else {
            NonTextFileView(fileDocument: document)
        }
    }

    private static func typeIdentifier(of item: CEWorkspaceFile) -> String {
        item.contentType?.identifier ?? "public.source-code"
    }

    static func synchronousDocument(of item: CEWorkspaceFile, limit: Int) -> CodeFileDocument? {
        guard item.byteCount <= limit else { return nil }
        let document = try? CodeFileDocument(
            for: item.url,
            withContentsOf: item.url,
            ofType: typeIdentifier(of: item)
        )
        return document ?? CodeFileDocument()
    }

    static func loadDocument(of item: CEWorkspaceFile, loader: CodeFileDiskLoader.Loader) async -> CodeFileDocument {
        let opened = try? await CodeFileDocument.open(
            contentsOf: item.url,
            ofType: typeIdentifier(of: item),
            loader: loader
        )
        return opened ?? CodeFileDocument()
    }
}
