//
//  CommandPaletteView.swift
//  Dreamder
//
//  Created by Alex Sinelnikov on 24.05.2022.
//

import SwiftUI

struct QuickActionsView: View {
    @Bindable private var state: QuickActionsViewModel

    private let closePalette: () -> Void

    init(state: QuickActionsViewModel, closePalette: @escaping () -> Void) {
        self.state = state
        self.closePalette = closePalette
        state.showAllCommands()
    }

    func callHandler(command: Command) {
        closePalette()
        state.run(command)
    }

    var body: some View {
        SearchPanelView<QuickSearchResultLabel, EmptyView, Command>(
            title: "Commands",
            image: Image(systemName: "magnifyingglass"),
            options: $state.filteredCommands,
            text: $state.commandQuery,
            alwaysShowOptions: true,
            optionRowHeight: 30,
            content: { command in
                QuickSearchResultLabel(
                    labelName: command.title,
                    charactersToHighlight: [],
                    nsLabelName: state.highlight(command.title)
                )
            },
            onRowClick: callHandler(command:),
            onClose: closePalette
        )
        .task(id: state.commandQuery) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            state.fetchMatchingCommands(val: state.commandQuery)
        }
    }
}
