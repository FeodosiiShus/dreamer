//
//  EditorTabBarTrailingAccessories.swift
//  Dreamder
//
//  Created by Austin Condiff on 9/7/23.
//

import Foundation
import SwiftUI

struct EditorTabBarTrailingAccessories: View {
    @Environment(\.controlActiveState)
    private var activeState

    @Environment(WorkspaceDocument.self) private var workspace

    @Environment(EditorManager.self) private var editorManager

    @Environment(Editor.self) private var editor

    @State private var isHovering = false

    private var markdownFileURL: URL? {
        let url = editor.selectedTab?.file.url
        return MarkdownPreviewLayoutStore.isMarkdownFile(url) ? url : nil
    }

    private var accessoryOpacity: Double {
        if activeState == .inactive {
            return 0.5
        }
        return editorManager.isFocusingActiveEditor ? 0.5 : 1
    }

    var body: some View {
        HStack(spacing: 2) {
            if let markdownFileURL {
                MarkdownPreviewLayoutButtons(
                    store: MarkdownPreviewLayoutStore.store(for: workspace),
                    url: markdownFileURL
                )
                .opacity(accessoryOpacity)
            }
            actionsMenu
        }
    }

    private var actionsMenu: some View {
        Menu {
            Button("Split Right") {
                editorManager.split(editor, .trailing, workspace: workspace)
            }
            Button("Split Down") {
                editorManager.split(editor, .bottom, workspace: workspace)
            }
            if editorManager.isInSplitter(editor) {
                Button("Unsplit") {
                    editorManager.unsplit(editor)
                }
                if editorManager.flattenedEditors.count > 2 {
                    Button("Unsplit All") {
                        editorManager.unsplitAll()
                    }
                }
                Button("Change Splitter Orientation") {
                    editorManager.changeSplitterOrientation(of: editor)
                }
            }
            Divider()
            Button("Close All") {
                closeAll()
            }
            .disabled(editor.tabs.isEmpty)
            Button("Close Others") {
                closeOthers()
            }
            .disabled(editor.tabs.count < 2)
        } label: {
            Image("general/moreVertical")
                .resizable()
                .frame(width: 16, height: 16)
                .frame(width: 26, height: 26)
                .background {
                    if isHovering {
                        Capsule()
                            .fill(Islands.tabHoverFill)
                    }
                }
                .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(editorManager.isFocusingActiveEditor)
        .opacity(accessoryOpacity)
        .help("Tab Actions")
        .onHover { isHovering = $0 }
    }

    private func closeAll() {
        withAnimation {
            editor.tabs.map(\.file).forEach { editor.closeTab(file: $0) }
        }
    }

    private func closeOthers() {
        guard let selected = editor.selectedTab?.file else { return }
        withAnimation {
            editor.tabs.map(\.file).filter { $0 != selected }.forEach { editor.closeTab(file: $0) }
        }
    }
}
