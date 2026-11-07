//
//  EditorTabBarTrailingAccessories.swift
//  Dreamder
//
//  Created by Austin Condiff on 9/7/23.
//

import Foundation
import SwiftUI

struct EditorTabBarTrailingAccessories: View {
    @Environment(\.splitEditor)
    private var splitEditor

    @Environment(\.controlActiveState)
    private var activeState

    @Environment(WorkspaceDocument.self) private var workspace

    @Environment(EditorManager.self) private var editorManager

    @Environment(Editor.self) private var editor

    private let markdownLayouts = MarkdownPreviewLayoutStore.shared

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
        Menu {
            if let markdownFileURL {
                markdownLayoutMenu(for: markdownFileURL)
            }
            Button("Split Right") {
                split(edge: .trailing)
            }
            Button("Split Down") {
                split(edge: .bottom)
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

    @ViewBuilder
    private func markdownLayoutMenu(for url: URL) -> some View {
        ForEach(MarkdownPreviewLayout.allCases) { mode in
            Toggle(mode.title, isOn: Binding(
                get: { markdownLayouts.layout(for: url) == mode },
                set: { isOn in
                    if isOn {
                        markdownLayouts.setLayout(mode, for: url)
                    }
                }
            ))
        }
        Divider()
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

    private func split(edge: Edge) {
        let newEditor: Editor
        if let tab = editor.selectedTab {
            newEditor = .init(files: [tab], temporaryTab: tab, workspace: workspace)
        } else {
            newEditor = .init()
        }
        splitEditor(edge, newEditor)
        editorManager.activeEditor = newEditor
    }
}
