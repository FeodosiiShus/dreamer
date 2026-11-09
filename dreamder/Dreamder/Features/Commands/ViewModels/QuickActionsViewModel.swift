//
//  CommandPaletteViewModel.swift
//  Dreamder
//
//  Created by Alex on 25.05.2022.
//

import AppKit
import Observation

@Observable
final class QuickActionsViewModel {
    var commandQuery: String = ""

    var filteredCommands: [Command] = []

    init() {}

    func reset() {
        commandQuery = ""
        showAllCommands()
    }

    func showAllCommands() {
        filteredCommands = CommandManager.shared.commands
    }

    func fetchMatchingCommands(val: String) {
        guard !val.isEmpty else {
            showAllCommands()
            return
        }
        filteredCommands = CommandManager.shared.commands.filter { $0.title.localizedCaseInsensitiveContains(val) }
    }

    func run(_ command: Command) {
        command.closureWrapper()
        commandQuery = ""
        filteredCommands = []
    }

    func highlight(_ commandTitle: String) -> NSAttributedString {
        let attribText = NSMutableAttributedString(string: commandTitle)
        let range = attribText.mutableString.range(of: commandQuery, options: .caseInsensitive)
        guard range.location != NSNotFound else { return attribText }
        attribText.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
        attribText.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize), range: range)
        return attribText
    }
}
