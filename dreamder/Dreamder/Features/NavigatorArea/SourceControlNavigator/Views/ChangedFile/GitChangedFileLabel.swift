//
//  GitChangedFileLabel.swift
//  Dreamder
//
//  Created by Khan Winter on 8/23/24.
//

import SwiftUI

struct GitChangedFileLabel: View {
    @Environment(WorkspaceDocument.self) private var workspace
    @Environment(SourceControlManager.self) private var sourceControlManager

    let file: GitChangedFile

    var body: some View {
        Label {
            Text(file.fileURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines))
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            if let ceFile = workspace.workspaceFileManager?.getFile(file.ceFileKey, createIfNotFound: true) {
                Image(nsImage: ceFile.nsIcon)
                    .renderingMode(.template)
            } else {
                Image(systemName: FileIcon.fileIcon(fileType: nil))
                    .renderingMode(.template)
            }
        }
    }
}

#Preview {
    Group {
        GitChangedFileLabel(file: GitChangedFile(
            status: .modified,
            stagedStatus: .none,
            fileURL: URL(filePath: "/Users/Dreamder/app.jsx"),
            originalFilename: nil
        ))
        .environment(SourceControlManager(workspaceURL: URL(filePath: "/Users/Dreamder"), editorManager: .init()))
        .environment(WorkspaceDocument())

        GitChangedFileLabel(file: GitChangedFile(
            status: .none,
            stagedStatus: .renamed,
            fileURL: URL(filePath: "/Users/Dreamder/app.jsx"),
            originalFilename: "app2.jsx"
        ))
        .environment(SourceControlManager(workspaceURL: URL(filePath: "/Users/Dreamder"), editorManager: .init()))
        .environment(WorkspaceDocument())
    }.padding()
}
