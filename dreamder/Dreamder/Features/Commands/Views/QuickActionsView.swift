//
//  CommandPaletteView.swift
//  Dreamder
//
//  Created by Alex Sinelnikov on 24.05.2022.
//

import SwiftUI

/// Quick actions view
struct QuickActionsView: View {

    @Environment(\.colorScheme)
    private var colorScheme: ColorScheme

    @Bindable private var state: QuickActionsViewModel

    private let commandManager = CommandManager.shared

    @State private var monitor: Any?

    @State private var selectedItem: Command?

    @State private var queryDebounce: Task<Void, Never>?

    private let closePalette: () -> Void

    init(state: QuickActionsViewModel, closePalette: @escaping () -> Void) {
        self.state = state
        self.closePalette = closePalette
        state.filteredCommands = commandManager.commands
    }

    func callHandler(command: Command) {
        closePalette()
        command.closureWrapper()
        selectedItem = nil
        state.commandQuery = ""
        state.filteredCommands = []
    }

    func onQueryChange(text: String) {
        state.commandQuery = text
        state.fetchMatchingCommands(val: text)
    }

    var body: some View {
        SearchPanelView<QuickSearchResultLabel, EmptyView, Command>(
            title: "Commands",
            image: Image(systemName: "magnifyingglass"),
            options: $state.filteredCommands,
            text: $state.commandQuery,
            alwaysShowOptions: true,
            optionRowHeight: 30
        ) { command in
            QuickSearchResultLabel(
                labelName: command.title,
                charactersToHighlight: [],
                nsLabelName: state.highlight(command.title)
            )
        } onRowClick: { command in
            callHandler(command: command)
        } onClose: {
            closePalette()
        }
        .onChange(of: state.commandQuery, initial: true) {
            queryDebounce?.cancel()
            queryDebounce = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                state.fetchMatchingCommands(val: state.commandQuery)
            }
        }
        .onDisappear {
            queryDebounce?.cancel()
        }
    }
}
