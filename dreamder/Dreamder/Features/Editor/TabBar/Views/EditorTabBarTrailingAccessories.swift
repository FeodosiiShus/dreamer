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

    @State private var isHovering: Bool

    init(isHovering: Bool = false) {
        _isHovering = State(initialValue: isHovering)
    }

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

    private var tabActions: EditorTabBarEditorActions {
        EditorTabBarEditorActions(editor: editor, editorManager: editorManager, workspace: workspace)
    }

    private var actionsMenu: some View {
        let actions = tabActions
        return Menu {
            Button("Split Right", action: actions.splitRight)
            Button("Split Down", action: actions.splitDown)
            if editorManager.isInSplitter(editor) {
                Button("Unsplit", action: actions.unsplit)
                if editorManager.flattenedEditors.count > 2 {
                    Button("Unsplit All", action: actions.unsplitAll)
                }
                Button("Change Splitter Orientation", action: actions.changeSplitterOrientation)
            }
            Divider()
            Button("Close All", action: actions.closeAll)
            .disabled(editor.tabs.isEmpty)
            Button("Close Others", action: actions.closeOthers)
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
        .onHover(perform: setHovering)
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }
}

struct EditorTabBarEditorActions {
    let editor: Editor
    let editorManager: EditorManager
    let workspace: WorkspaceDocument

    func splitRight() {
        editorManager.split(editor, .trailing, workspace: workspace)
    }

    func splitDown() {
        editorManager.split(editor, .bottom, workspace: workspace)
    }

    func unsplit() {
        editorManager.unsplit(editor)
    }

    func unsplitAll() {
        editorManager.unsplitAll()
    }

    func changeSplitterOrientation() {
        editorManager.changeSplitterOrientation(of: editor)
    }

    func closeAll() {
        withAnimation {
            editor.closeUnpinnedTabs()
        }
    }

    func closeOthers() {
        guard let selected = editor.selectedTab?.file else { return }
        withAnimation {
            editor.closeUnpinnedTabs { $0 != selected }
        }
    }
}
