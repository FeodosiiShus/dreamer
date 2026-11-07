//
//  TabManager.swift
//  Dreamder
//
//  Created by Wouter Hennen on 03/03/2023.
//

import Combine
import Foundation
import Observation
import DequeModule
import OrderedCollections
import SwiftUI
import os

@Observable
class EditorManager {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "EditorManager")

    /// The complete editor layout.
    var editorLayout: EditorLayout

    var isFocusingActiveEditor: Bool

    /// The Editor with active focus.
    var activeEditor: Editor {
        didSet {
            activeEditorHistory.prepend { [weak oldValue] in oldValue }
        }
    }

    /// History of last-used editors.
    @ObservationIgnored var activeEditorHistory: Deque<() -> Editor?> = []

    /// notify listeners whenever tab selection changes on the active editor.
    @ObservationIgnored var tabBarTabIdSubject = PassthroughSubject<Editor.Tab?, Never>()
    @ObservationIgnored private var selectionObservation: Task<Void, Never>?

    var flattenedEditors: [Editor] {
        getFlattened()
    }

    // MARK: - Init

    init() {
        let tab = Editor()
        self.activeEditor = tab
        self.activeEditorHistory.prepend { [weak tab] in tab }
        self.editorLayout = .horizontal(.init(.horizontal, editorLayouts: [.one(tab)]))
        self.isFocusingActiveEditor = false
        observeActiveSelection()
    }

    /// Initializes the editor manager's state to the "initial" state.
    ///
    /// Functionally identical to the initializer for this class.
    func initCleanState() {
        let tab = Editor()
        self.activeEditor = tab
        self.activeEditorHistory.prepend { [weak tab] in tab }
        self.editorLayout = .horizontal(.init(.horizontal, editorLayouts: [.one(tab)]))
        self.isFocusingActiveEditor = false
    }

    /// Flattens the splitviews.
    func flatten() {
        switch editorLayout {
        case .horizontal(let data), .vertical(let data):
            data.flatten()
        default:
            break
        }
    }

    /// Returns and array of flattened splitviews.
    func getFlattened() -> [Editor] {
        switch editorLayout {
        case .horizontal(let data), .vertical(let data):
            return data.getFlattened()
        default:
            return []
        }
    }

    /// Opens a new tab in a editor.
    /// - Parameters:
    ///   - item: The tab to open.
    ///   - editor: The editor to add the tab to. If nil, it is added to the active tab group.
    ///   - asTemporary: Indicates whether the tab should be opened as a temporary tab or a permanent tab.
    func openTab(item: CEWorkspaceFile, in editor: Editor? = nil, asTemporary: Bool = false) {
        let editor = editor ?? activeEditor
        editor.openTab(file: item, asTemporary: asTemporary)
    }

    @discardableResult
    func splitActiveEditor(_ edge: Edge, workspace: WorkspaceDocument?) -> Editor? {
        split(activeEditor, edge, workspace: workspace)
    }

    @discardableResult
    func split(_ source: Editor, _ edge: Edge, workspace: WorkspaceDocument?) -> Editor? {
        guard let parent = source.parent, let index = parent.indexOfEditor(source) else {
            return nil
        }
        let newEditor: Editor
        if let tab = source.selectedTab {
            newEditor = Editor(files: [tab], temporaryTab: tab, workspace: workspace)
        } else {
            newEditor = Editor(files: OrderedSet<Editor.Tab>(), workspace: workspace)
        }
        parent.split(edge, at: index, new: newEditor)
        activeEditor = newEditor
        return newEditor
    }

    @discardableResult
    func moveTabToNewSplit(
        _ file: CEWorkspaceFile,
        from source: Editor,
        edge: Edge,
        workspace: WorkspaceDocument?
    ) -> Editor? {
        guard let parent = source.parent, let index = parent.indexOfEditor(source) else {
            return nil
        }
        let newEditor = Editor(files: [file], workspace: workspace)
        parent.split(edge, at: index, new: newEditor)
        source.closeTab(file: file)
        activeEditor = newEditor
        return newEditor
    }

    // MARK: - Splitter Navigation

    private var rootSplitData: SplitViewData? {
        editorLayout.splitData
    }

    func isInSplitter(_ editor: Editor) -> Bool {
        guard let parent = editor.parent else { return false }
        return parent.editorLayouts.count > 1
    }

    func nextSplitEditor(after editor: Editor) -> Editor? {
        let editors = flattenedEditors
        guard let index = editors.firstIndex(where: { $0 === editor }) else { return nil }
        return editors[(index + 1) % editors.count]
    }

    func previousSplitEditor(before editor: Editor) -> Editor? {
        let editors = flattenedEditors
        guard let index = editors.firstIndex(where: { $0 === editor }) else { return nil }
        return editors[(index + editors.count - 1) % editors.count]
    }

    @discardableResult
    func unsplit(_ editor: Editor) -> Bool {
        guard isInSplitter(editor), let parent = editor.parent, let root = rootSplitData else { return false }
        let siblings = parent.getFlattened().filter { $0 !== editor }
        let replaced: Bool
        if root === parent {
            parent.weights = [1]
            parent.editorLayouts = [.one(editor)]
            editor.parent = parent
            replaced = true
        } else {
            replaced = root.replaceChild(parent, with: .one(editor))
        }
        guard replaced else { return false }

        let selectedFile = editor.selectedTab?.file
        var mergedFiles: [CEWorkspaceFile] = []
        for sibling in siblings {
            for tab in sibling.tabs where !editor.tabs.contains(tab) {
                editor.tabs.append(tab)
                mergedFiles.append(tab.file)
            }
            sibling.parent = nil
        }
        if let kept = selectedFile ?? mergedFiles.first {
            editor.setSelectedTab(kept)
        }
        if activeEditor !== editor {
            activeEditor = editor
        }
        return true
    }

    func unsplitAll() {
        while isInSplitter(activeEditor), unsplit(activeEditor) {}
    }

    @discardableResult
    func changeSplitterOrientation(of editor: Editor) -> Bool {
        guard isInSplitter(editor), let parent = editor.parent, let root = rootSplitData else { return false }
        parent.axis = parent.axis == .horizontal ? .vertical : .horizontal
        let layout = EditorLayout.container(for: parent)
        if root === parent {
            editorLayout = layout
        } else {
            root.replaceChild(parent, with: layout)
        }
        return true
    }

    private func observeActiveSelection() {
        selectionObservation = Task { [weak self] in
            let selections = Observations { [weak self] in self?.activeEditor.selectedTab }
            for await tab in selections {
                guard let self else { return }
                tabBarTabIdSubject.send(tab)
            }
        }
    }

    isolated deinit {
        selectionObservation?.cancel()
    }

    // MARK: - Close Editor

    /// Close an editor and fix editor manager state, updating active editor, etc.
    /// - Parameter editor: The editor to close
    func closeEditor(_ editor: Editor) {
        editor.close()
        if activeEditor == editor {
            setNewActiveEditor(excluding: editor)
        }

        flatten()
    }

    /// Set a new active editor.
    /// - Parameter editor: The editor to exclude.
    func setNewActiveEditor(excluding editor: Editor) {
        activeEditorHistory.removeAll { $0() == nil || $0() == editor }
        if activeEditorHistory.isEmpty {
            activeEditor = findSomeEditor(excluding: editor)
        } else {
            activeEditor = activeEditorHistory.removeFirst()() ?? findSomeEditor(excluding: editor)
        }
    }

    /// Find some editor, or if one cannot be found set up the editor manager with a clean state.
    /// - Parameter editor: The editor to exclude.
    /// - Returns: Some editor, order is not guaranteed.
    func findSomeEditor(excluding editor: Editor) -> Editor {
        guard let someEditor = editorLayout.findSomeEditor(except: editor) else {
            initCleanState()
            return activeEditor
        }
        return someEditor
    }

    // MARK: - Focus

    func toggleFocusingEditor(from editor: Editor) {
        if !isFocusingActiveEditor {
            activeEditor = editor
        }
        isFocusingActiveEditor.toggle()
    }
}
