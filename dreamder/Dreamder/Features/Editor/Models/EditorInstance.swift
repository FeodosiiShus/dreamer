//
//  EditorInstance.swift
//  Dreamder
//
//  Created by Khan Winter on 1/4/24.
//

import Foundation
import AppKit
import Observation
import CodeEditTextView
import CodeEditSourceEditor

/// A single instance of an editor in a group with an observable ``EditorInstance/cursorPositions`` variable
/// tracking the user's current location in a file.
@Observable
class EditorInstance: Hashable {
    /// The file presented in this editor instance.
    let file: CEWorkspaceFile

    var cursorPositions: [CursorPosition]
    var scrollPosition: CGPoint?
    var requestedScrollPosition: CGPoint?

    var findText: String?
    var replaceText: String?

    @ObservationIgnored let actions: EditorActionCoordinator
    @ObservationIgnored let rangeTranslator: RangeTranslator

    var wrapLinesOverride: Bool?

    @ObservationIgnored private var observationTasks: [Task<Void, Never>] = []

    // MARK: - Init

    init(workspace: WorkspaceDocument?, file: CEWorkspaceFile, cursorPositions: [CursorPosition]? = nil) {
        self.file = file
        let url = file.url
        let actions = EditorActionCoordinator(file: file)
        self.actions = actions
        self.rangeTranslator = RangeTranslator(actions: actions)
        let editorState = EditorStateRestoration.shared?.restorationState(for: url)

        findText = workspace?.searchState?.searchQuery
        replaceText = workspace?.searchState?.replaceText

        self.cursorPositions = (
            cursorPositions ?? editorState?.editorCursorPositions ?? [CursorPosition(line: 1, column: 1)]
        )
        self.scrollPosition = editorState?.scrollPosition
        self.requestedScrollPosition = editorState?.scrollPosition

        observationTasks.append(persistRestorationState(for: url))
        if let searchState = workspace?.searchState {
            observationTasks.append(contentsOf: syncFindText(with: searchState))
            observationTasks.append(contentsOf: syncReplaceText(with: searchState))
        }
    }

    isolated deinit {
        observationTasks.forEach { $0.cancel() }
    }

    private static let restorationDebounce: Duration = .milliseconds(100)

    private func persistRestorationState(for url: URL) -> Task<Void, Never> {
        Task { [weak self] in
            var pendingSave: Task<Void, Never>?
            var lastPersisted: (cursorPositions: [CursorPosition], scrollPosition: CGPoint?)?
            let changes = Observations { [weak self] in
                self.map { (cursorPositions: $0.cursorPositions, scrollPosition: $0.scrollPosition) }
            }
            for await observed in changes {
                guard let change = observed else { continue }
                if let lastPersisted,
                   lastPersisted.cursorPositions == change.cursorPositions,
                   lastPersisted.scrollPosition == change.scrollPosition {
                    continue
                }
                lastPersisted = change
                pendingSave?.cancel()
                pendingSave = Task {
                    try? await Task.sleep(for: Self.restorationDebounce)
                    guard !Task.isCancelled else { return }
                    EditorStateRestoration.shared?.updateRestorationState(
                        for: url,
                        data: .init(
                            cursorPositions: change.cursorPositions,
                            scrollPosition: change.scrollPosition ?? .zero
                        )
                    )
                }
            }
            pendingSave?.cancel()
        }
    }

    // MARK: - Find/Replace Sync

    private func syncFindText(with searchState: WorkspaceDocument.SearchState) -> [Task<Void, Never>] {
        let fromSearch = Task { [weak self, weak searchState] in
            let queries = Observations { [weak searchState] in searchState?.searchQuery }
            for await query in queries {
                guard let self, let query, findText != query else { continue }
                findText = query
            }
        }
        let toSearch = Task { [weak self, weak searchState] in
            let texts = Observations { [weak self] in self?.findText }
            for await text in texts {
                guard let self, let searchState else { continue }
                if let text {
                    if searchState.searchQuery != text {
                        searchState.searchQuery = text
                    }
                } else if findText != searchState.searchQuery {
                    findText = searchState.searchQuery
                }
            }
        }
        return [fromSearch, toSearch]
    }

    private func syncReplaceText(with searchState: WorkspaceDocument.SearchState) -> [Task<Void, Never>] {
        let fromSearch = Task { [weak self, weak searchState] in
            let replacements = Observations { [weak searchState] in searchState?.replaceText }
            for await replacement in replacements {
                guard let self, let replacement, replaceText != replacement else { continue }
                replaceText = replacement
            }
        }
        let toSearch = Task { [weak self, weak searchState] in
            let texts = Observations { [weak self] in self?.replaceText }
            for await text in texts {
                guard let self, let searchState else { continue }
                if let text {
                    if searchState.replaceText != text {
                        searchState.replaceText = text
                    }
                } else if replaceText != searchState.replaceText {
                    replaceText = searchState.replaceText
                }
            }
        }
        return [fromSearch, toSearch]
    }

    // MARK: - Soft Wraps

    func toggleSoftWraps() {
        guard let wraps = actions.toggleSoftWraps() else { return }
        wrapLinesOverride = wraps
    }

    // MARK: - Hashable, Equatable

    func hash(into hasher: inout Hasher) {
        hasher.combine(file)
    }

    static func == (lhs: EditorInstance, rhs: EditorInstance) -> Bool {
        lhs.file == rhs.file
    }

    // MARK: - RangeTranslator

    /// Translates ranges (eg: from a cursor position) to other information like the number of lines in a range.
    class RangeTranslator: TextViewCoordinator {
        private weak var textViewController: TextViewController?
        private let actions: EditorActionCoordinator

        init(actions: EditorActionCoordinator = EditorActionCoordinator()) {
            self.actions = actions
        }

        func prepareCoordinator(controller: TextViewController) {
            self.textViewController = controller
            actions.prepareCoordinator(controller: controller)
        }

        func controllerDidAppear(controller: TextViewController) {
            actions.controllerDidAppear(controller: controller)
            if controller.isEditable && controller.isSelectable {
                controller.view.window?.makeFirstResponder(controller.textView)
            }
        }

        func destroy() {
            self.textViewController = nil
            actions.destroy()
        }

        /// Returns the lines contained in the given range.
        /// - Parameter range: The range to use.
        /// - Returns: The number of lines contained by the given range. Or `0` if the text view could not be found,
        ///            or lines could not be found for the given range.
        func linesInRange(_ range: NSRange) -> Int {
            guard let controller = textViewController,
                  let textView = controller.textView,
                  // Find the lines at the beginning and end of the range
                  let startTextLine = textView.layoutManager.textLineForOffset(range.location),
                  let endTextLine = textView.layoutManager.textLineForOffset(range.upperBound) else {
                return 0
            }
            return (endTextLine.index - startTextLine.index) + 1
        }

        func moveLinesUp() {
            actions.moveLines(up: true)
        }

        func moveLinesDown() {
            actions.moveLines(up: false)
        }
    }
}
