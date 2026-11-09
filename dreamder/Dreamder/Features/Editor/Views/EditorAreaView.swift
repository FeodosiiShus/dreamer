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

    let editor: Editor

    @FocusState.Binding var focus: Editor?

    @Environment(EditorManager.self) private var editorManager

    @Environment(WorkspaceDocument.self) private var workspace

    @State var codeFile: (() -> CodeFileDocument?)?

    typealias DocumentLoader = () -> CodeFileDocument?

    static let noDocument: DocumentLoader = { nil }

    init(editor: Editor, focus: FocusState<Editor?>.Binding) {
        self.editor = editor
        self._focus = focus
        self.codeFile = Self.loader(for: editor.selectedTab?.file.fileDocument)
    }

    private var shouldShowTabBar: Bool {
        Self.showsTabBar(style: navigationStyle, editors: editorManager.flattenedEditors)
    }

    static func showsTabBar(style: SettingsData.NavigationStyle, editors: [Editor]) -> Bool {
        style == .openInTabs || editors.contains { editor in
            (editor.temporaryTab == nil && !editor.tabs.isEmpty)
            || (editor.temporaryTab != nil && editor.tabs.count > 1)
        }
    }

    @ViewBuilder private var editorContent: some View {
        if let selected = editor.selectedTab {
            if let document = codeFile?() {
                EditorAreaFileView(editorInstance: selected, codeFile: document)
                    .opacity(
                        Self.opacity(
                            dimsWithoutFocus: dimEditorsWithoutFocus,
                            isActive: editor == editorManager.activeEditor
                        )
                    )
                    .onDrop(of: [.fileURL], isTargeted: nil, perform: dropHandler)
            } else {
                LoadingFileView(selected.file.name)
                    .onAppear {
                        codeFile = Self.keepingCurrent(codeFile, unless: selected.file.fileDocument)
                    }
            }
        } else {
            Self.emptyState()
                .onTapGesture(perform: Self.activateAction(editor, in: editorManager))
                .onDrop(of: [.fileURL], isTargeted: nil, perform: dropHandler)
        }
    }

    static func emptyState() -> EditorEmptyStateView {
        EditorEmptyStateView(sendAction: MenuResponderChain.send)
    }

    private var dropHandler: ([NSItemProvider]) -> Bool {
        Self.makeDropHandler(editor: editor, editorManager: editorManager)
    }

    var body: some View {
        VStack(spacing: 0) {
            if shouldShowTabBar {
                EditorTabBarView()
                    .id("TabBarView" + editor.id.uuidString)
                    .environment(editor)
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
        .onChange(of: editor.selectedTab) { _, newValue in
            codeFile = Self.keepingCurrent(codeFile, unless: newValue?.file.fileDocument)
        }
        .onChange(of: Self.loadedDocument(of: editor.selectedTab)) { old, new in
            if let loader = Self.loader(afterLoadedDocumentChangedFrom: old, to: new, in: editor.selectedTab) {
                codeFile = loader
            }
        }
    }

    static func makeDropHandler(editor: Editor, editorManager: EditorManager) -> ([NSItemProvider]) -> Bool {
        { providers in
            for provider in providers {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else {
                        return
                    }

                    Task { @MainActor in
                        let file = CEWorkspaceFile(url: url)
                        editorManager.activeEditor = editor
                        editor.openTab(file: file)
                    }
                }
            }
            return true
        }
    }

    static func loader(for document: CodeFileDocument?) -> DocumentLoader? {
        guard let document else { return nil }
        return { [weak document] in document }
    }

    static func loaderOrEmpty(for document: CodeFileDocument?) -> DocumentLoader {
        if let loader = loader(for: document) {
            return loader
        }
        return noDocument
    }

    static func keepingCurrent(_ current: DocumentLoader?, unless document: CodeFileDocument?) -> DocumentLoader? {
        if let loader = loader(for: document) {
            return loader
        }
        return current
    }

    struct LoadedDocument: Equatable {
        let fileID: CEWorkspaceFile.ID
        let document: ObjectIdentifier?
    }

    static func loadedDocument(of tab: Editor.Tab?) -> LoadedDocument? {
        guard let tab else { return nil }
        return LoadedDocument(fileID: tab.file.id, document: tab.file.fileDocument.map(ObjectIdentifier.init))
    }

    static func loader(
        afterLoadedDocumentChangedFrom old: LoadedDocument?,
        to new: LoadedDocument?,
        in tab: Editor.Tab?
    ) -> DocumentLoader? {
        guard let old, let new, old.fileID == new.fileID else { return nil }
        return loaderOrEmpty(for: tab?.file.fileDocument)
    }

    static func opacity(dimsWithoutFocus: Bool, isActive: Bool) -> Double {
        guard dimsWithoutFocus else { return 1 }
        return isActive ? 1 : 0.5
    }

    static func activate(_ editor: Editor, in editorManager: EditorManager) {
        editorManager.activeEditor = editor
    }

    static func activateAction(_ editor: Editor, in editorManager: EditorManager) -> () -> Void {
        { activate(editor, in: editorManager) }
    }

    static func adoptTemporaryTabAction(
        in editor: Editor
    ) -> (SettingsData.NavigationStyle, SettingsData.NavigationStyle) -> Void {
        { _, newStyle in adoptTemporaryTab(in: editor, for: newStyle) }
    }

    static func adoptTemporaryTab(in editor: Editor, for style: SettingsData.NavigationStyle) {
        if style == .openInPlace && editor.tabs.count == 1 {
            editor.temporaryTab = editor.tabs[0]
        }
    }
}
