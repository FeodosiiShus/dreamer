//
//  IgnoredFilesListView.swift
//  Dreamder
//
//  Created by Austin Condiff on 11/1/24.
//

import SwiftUI

struct IgnoredFilesListView: View {
    @State private var model: IgnorePatternModel

    init(model: IgnorePatternModel = IgnorePatternModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        GlobPatternList(
            patterns: $model.patterns,
            selection: $model.selection,
            addPattern: model.addPattern,
            removePatterns: model.removePatterns,
            emptyMessage: "No ignored files"
        )
        .task {
            await model.start()
        }
    }
}
