//
//  EditorAreaFileView.swift
//  Dreamder
//
//  Created by Pavel Kasila on 20.03.22.
//

import AppKit
import AVKit
import CodeEditSourceEditor
import SwiftUI

struct EditorAreaFileView: View {

    @Environment(StatusBarViewModel.self) private var statusBarViewModel

    var editorInstance: EditorInstance
    var codeFile: CodeFileDocument

    @ViewBuilder var editorAreaFileView: some View {
        if let utType = codeFile.utType, utType.conforms(to: .text) {
            if MarkdownPreviewLayoutStore.isMarkdownFile(codeFile.fileURL) {
                MarkdownEditorWithPreview(
                    editorInstance: editorInstance,
                    codeFile: codeFile
                )
                .id(CodeFileViewIdentity(editorInstance: editorInstance, codeFile: codeFile))
            } else {
                CodeFileView(
                    editorInstance: editorInstance,
                    codeFile: codeFile
                )
                .id(CodeFileViewIdentity(editorInstance: editorInstance, codeFile: codeFile))
            }
        } else {
            NonTextFileView(fileDocument: codeFile)
                .modifier(UpdateStatusBarInfo(with: codeFile.fileURL))
                .onDisappear {
                    statusBarViewModel.dimensions = nil
                    statusBarViewModel.fileSize = nil
                }
        }
    }

    var body: some View {
        editorAreaFileView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .pointerStyle(.horizontalText)
    }
}
