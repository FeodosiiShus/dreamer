//
//  OpenQuicklyPreviewView.swift
//  DreamderModules/QuickOpen
//
//  Created by Pavel Kasila on 20.03.22.
//

import SwiftUI

struct OpenQuicklyPreviewView: View {

    private let item: CEWorkspaceFile

    @State private var editorInstance: EditorInstance
    @State private var document: CodeFileDocument

    @State private var undoRegistration = UndoManagerRegistration()

    init(item: CEWorkspaceFile) {
        self.item = item
        let doc = try? CodeFileDocument(
            for: item.url,
            withContentsOf: item.url,
            ofType: item.contentType?.identifier ?? "public.source-code"
        )
        self._editorInstance = State(wrappedValue: EditorInstance(workspace: nil, file: item))
        self._document = State(wrappedValue: doc ?? .init())
    }

    var body: some View {
        if let utType = document.utType, utType.conforms(to: .text) {
            CodeFileView(editorInstance: editorInstance, codeFile: document, isEditable: false)
                .environment(undoRegistration)
        } else {
            NonTextFileView(fileDocument: document)
        }
    }
}
