//
//  SplitViewData.swift
//  Dreamder
//
//  Created by Wouter Hennen on 16/02/2023.
//

import SwiftUI
import Observation

@Observable
final class SplitViewData {
    var editorLayouts: [EditorLayout] {
        didSet {
            if weights.count != editorLayouts.count {
                weights = Self.equalWeights(count: editorLayouts.count)
            }
        }
    }

    var weights: [CGFloat]

    var axis: Axis

    init(_ axis: Axis, editorLayouts: [EditorLayout] = [], weights: [CGFloat]? = nil) {
        self.editorLayouts = editorLayouts
        self.axis = axis
        self.weights = Self.normalizedWeights(weights, count: editorLayouts.count)

        editorLayouts.forEach {
            if case .one(let editor) = $0 {
                editor.parent = self
            }
        }
    }

    nonisolated static func equalWeights(count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        return Array(repeating: 1 / CGFloat(count), count: count)
    }

    nonisolated static func normalizedWeights(_ weights: [CGFloat]?, count: Int) -> [CGFloat] {
        guard let weights,
              weights.count == count,
              count > 0,
              weights.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            return equalWeights(count: count)
        }
        let total = weights.reduce(0, +)
        guard total > 0 else { return equalWeights(count: count) }
        return weights.map { $0 / total }
    }

    /// Splits the editor at a certain index into two separate editors.
    /// - Parameters:
    ///   - direction: direction in which the editor will be split.
    ///   If the direction is the same as the ancestor direction,
    ///   the editor is added to the ancestor instead of creating a new split container.
    ///   - index: index where the divider will be added.
    ///   - editor: new editor class that will be used for the editor.
    func split(_ direction: Edge, at index: Int, new editor: Editor) {
        guard editorLayouts.indices.contains(index) else { return }
        editor.parent = self
        var newWeights = currentWeights
        let existing = newWeights[index]
        let half = existing / 2
        switch (axis, direction) {
        case (.horizontal, .trailing), (.vertical, .bottom):
            newWeights[index] = half
            newWeights.insert(half, at: index + 1)
            weights = newWeights
            editorLayouts.insert(.one(editor), at: index + 1)

        case (.horizontal, .leading), (.vertical, .top):
            newWeights[index] = half
            newWeights.insert(half, at: index)
            weights = newWeights
            editorLayouts.insert(.one(editor), at: index)

        case (.horizontal, .top):
            editorLayouts[index] = .vertical(.init(.vertical, editorLayouts: [.one(editor), editorLayouts[index]]))

        case (.horizontal, .bottom):
            editorLayouts[index] = .vertical(.init(.vertical, editorLayouts: [editorLayouts[index], .one(editor)]))

        case (.vertical, .leading):
            editorLayouts[index] = .horizontal(.init(.horizontal, editorLayouts: [.one(editor), editorLayouts[index]]))

        case (.vertical, .trailing):
            editorLayouts[index] = .horizontal(.init(.horizontal, editorLayouts: [editorLayouts[index], .one(editor)]))
        }
    }

    var currentWeights: [CGFloat] {
        Self.normalizedWeights(weights, count: editorLayouts.count)
    }

    /// Closes an Editor.
    /// - Parameter id: ID of the Editor.
    func closeEditor(with id: Editor.ID) {
        guard let index = editorLayouts.firstIndex(where: { layout in
            if case .one(let editor) = layout { return editor.id == id }
            return false
        }) else { return }
        var newWeights = currentWeights
        let freed = newWeights.remove(at: index)
        if !newWeights.isEmpty {
            newWeights[index > 0 ? index - 1 : 0] += freed
        }
        weights = newWeights
        editorLayouts.remove(at: index)
    }

    func getEditorLayout(with id: Editor.ID) -> EditorLayout? {
        for editorLayout in editorLayouts {
            if case .one(let editor) = editorLayout {
                if editor.id == id {
                    return editorLayout
                }
            }
        }

        return nil
    }

    /// Flattens the splitviews.
    func flatten() {
        for index in editorLayouts.indices {
            editorLayouts[index].flatten(parent: self)
        }
    }

    func indexOfEditor(_ editor: Editor) -> Int? {
        editorLayouts.firstIndex { layout in
            if case .one(let candidate) = layout { return candidate === editor }
            return false
        }
    }

    @discardableResult
    func replaceChild(_ target: SplitViewData, with layout: EditorLayout) -> Bool {
        for index in editorLayouts.indices {
            guard let child = editorLayouts[index].splitData else { continue }
            if child === target {
                if case .one(let editor) = layout {
                    editor.parent = self
                }
                editorLayouts[index] = layout
                return true
            }
            if child.replaceChild(target, with: layout) {
                return true
            }
        }
        return false
    }

    /// Gets flattened splitviews.
    func getFlattened() -> [Editor] {
        var arr: [Editor] = []
        for index in editorLayouts.indices {
            arr += editorLayouts[index].getFlattened(parent: self)
        }
        return arr
    }
}
