//
//  EditorLayoutView.swift
//  Dreamder
//
//  Created by Wouter Hennen on 20/02/2023.
//

import SwiftUI

struct EditorLayoutView: View {
    var layout: EditorLayout

    @FocusState.Binding var focus: Editor?

    var body: some View {
        Group {
            switch layout {
            case .one(let detailEditor):
                EditorAreaView(editor: detailEditor, focus: $focus)
            case .vertical(let data), .horizontal(let data):
                SubEditorLayoutView(data: data, focus: $focus)
            }
        }
    }

    struct SubEditorLayoutView: View {
        let data: SplitViewData
        @FocusState.Binding var focus: Editor?

        var body: some View {
            SplitView(axis: data.axis, dividerStyle: .editorDivider) {
                splitView
            }
            .edgesIgnoringSafeArea([.top, .bottom])
        }

        var splitView: some View {
            ForEach(Array(data.editorLayouts.enumerated()), id: \.offset) { index, item in
                EditorLayoutView(layout: item, focus: $focus)
                   .transformEnvironment(\.isEditorLayoutAtEdge) { belowToolbar in
                       calcIsAtEdge(current: &belowToolbar, index: index)
                   }
                   .environment(\.splitEditor, splitAction(at: index))
            }
        }

        func splitAction(at index: Int) -> (Edge, Editor) -> Void {
            { [weak data] edge, newEditor in
                data?.split(edge, at: index, new: newEditor)
            }
        }

        func calcIsAtEdge(current: inout VerticalEdge.Set, index: Int) {
            if case .vertical = data.axis {
                guard data.editorLayouts.count != 1 else { return }
                if index == data.editorLayouts.count - 1 {
                    current.remove(.top)
                } else if index == 0 {
                    current.remove(.bottom)
                } else {
                    current = []
                }
            }
        }
    }
}

struct BelowToolbarEnvironmentKey: EnvironmentKey {
    static var defaultValue: VerticalEdge.Set = .all
}

extension EnvironmentValues {
    var isEditorLayoutAtEdge: BelowToolbarEnvironmentKey.Value {
        get { self[BelowToolbarEnvironmentKey.self] }
        set { self[BelowToolbarEnvironmentKey.self] = newValue }
    }
}
