//
//  WindowCodeFileView.swift
//  Dreamder
//
//  Created by Khan Winter on 3/19/23.
//

import Foundation
import SwiftUI

/// # Should **not** be used other than in a single file window.
struct WindowCodeFileView: View {
    @State private var editorInstance: EditorInstance
    @State private var undoRegistration = UndoManagerRegistration()
    var codeFile: CodeFileDocument

    init(codeFile: CodeFileDocument) {
        self._editorInstance = State(
            wrappedValue: EditorInstance(
                workspace: nil,
                file: CEWorkspaceFile(url: codeFile.fileURL ?? URL(fileURLWithPath: ""))
            )
        )
        self.codeFile = codeFile
    }

    var body: some View {
        if let utType = codeFile.utType, utType.conforms(to: .text) {
            CodeFileView(editorInstance: editorInstance, codeFile: codeFile)
                .environment(undoRegistration)
        } else {
            NonTextFileView(fileDocument: codeFile)
        }
    }
}
