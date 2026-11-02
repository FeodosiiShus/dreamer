//
//  EditorAreaView.swift
//  Dreamder
//
//  Created by Wouter Hennen on 16/02/2023.
//

import SwiftUI
import CodeEditTextView
import UniformTypeIdentifiers

struct EditorAreaView: View {
    @AppSettings(\.navigation.navigationStyle)
    var navigationStyle

    @AppSettings(\.general.dimEditorsWithoutFocus)
    var dimEditorsWithoutFocus

    @ObservedObject var editor: Editor

    @FocusState.Binding var focus: Editor?

    @EnvironmentObject private var editorManager: EditorManager

    @EnvironmentObject private var workspace: WorkspaceDocument

    @State var codeFile: (() -> CodeFileDocument?)?

    init(editor: Editor, focus: FocusState<Editor?>.Binding) {
        self.editor = editor
        self._focus = focus
        if let file = editor.selectedTab?.file.fileDocument {
            self.codeFile = { [weak file] in file }
        }
    }

    private var shouldShowTabBar: Bool {
        return navigationStyle == .openInTabs
        || editorManager.flattenedEditors.contains { editor in
            (editor.temporaryTab == nil && !editor.tabs.isEmpty)
            || (editor.temporaryTab != nil && editor.tabs.count > 1)
        }
    }

    @ViewBuilder private var editorContent: some View {
        if let selected = editor.selectedTab {
            if let codeFile = codeFile?() {
                EditorAreaFileView(editorInstance: selected, codeFile: codeFile)
                    .focusedObject(editor)
                    .opacity(dimEditorsWithoutFocus && editor != editorManager.activeEditor ? 0.5 : 1)
                    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                        _ = handleDrop(providers: providers)
                        return true
                    }
            } else {
                LoadingFileView(selected.file.name)
                    .onAppear {
                        if let file = selected.file.fileDocument {
                            self.codeFile = { [weak file] in file }
                        }
                    }
                    .onReceive(selected.file.fileDocumentPublisher) { latestValue in
                        self.codeFile = { [weak latestValue] in latestValue }
                    }
            }
        } else {
            EditorEmptyStateView()
                .onTapGesture {
                    editorManager.activeEditor = editor
                }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    _ = handleDrop(providers: providers)
                    return true
                }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if shouldShowTabBar {
                EditorTabBarView()
                    .id("TabBarView" + editor.id.uuidString)
                    .environmentObject(editor)
                    .environment(\.isActiveEditor, editor == editorManager.activeEditor)
            }
            if let fileURL = editor.selectedTab?.file.url {
                MergeConflictEditorBanner(fileURL: fileURL)
            }
            editorContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let selected = editor.selectedTab, let document = codeFile?() {
                EditorBreadcrumbsBar(editorInstance: selected, codeFile: document)
                    .id(ObjectIdentifier(selected))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if editorManager.activeEditor === editor {
                InspectionWidget(editor: editor)
                    .padding(.trailing, shouldShowTabBar ? 36 : 12)
                    .padding(.top, shouldShowTabBar ? (EditorTabBarView.height - 24) / 2 : 8)
            }
        }
        .focused($focus, equals: editor)
        .task {
            if let manager = workspace.sourceControlManager {
                MergeConflictsCenter.shared.monitor(manager)
            }
        }
        .onChange(of: navigationStyle) { _, newValue in
            if newValue == .openInPlace && editor.tabs.count == 1 {
                editor.temporaryTab = editor.tabs[0]
            }
        }
        .onChange(of: editor.selectedTab) { _, newValue in
            if let file = newValue?.file.fileDocument {
                codeFile = { [weak file] in file }
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }

                DispatchQueue.main.async {
                    let file = CEWorkspaceFile(url: url)
                    editorManager.activeEditor = editor
                    editor.openTab(file: file)
                }
            }
        }
        return true
    }
}
