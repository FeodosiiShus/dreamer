//
//  SearchSettingsView.swift
//  Dreamder
//
//  Created by Esteban on 12/10/23.
//

import SwiftUI

struct SearchSettingsView: View {
    private let model: SearchSettingsModel

    init(model: SearchSettingsModel = .shared) {
        self.model = model
    }

    var body: some View {
        SettingsForm {
            Section {
                ExcludedGlobPatternList(model: model)
            } header: {
                Text("Exclude")
                Text(
                    "Add glob patterns to exclude matching files and folders from searches and open quickly. " +
                    "This will inherit glob patterns from the Exclude from Project setting."
                )
            }
        }
    }
}

struct ExcludedGlobPatternList: View {
    @Bindable private var model: SearchSettingsModel

    init(model: SearchSettingsModel) {
        self.model = model
    }

    var body: some View {
        GlobPatternList(
            patterns: $model.ignoreGlobPatterns,
            selection: $model.selection,
            addPattern: model.addPattern,
            removePatterns: model.removePatterns,
            emptyMessage: "No excluded glob patterns"
        )
    }
}
