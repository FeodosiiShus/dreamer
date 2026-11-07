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
