import Foundation
import Testing
@testable import Dreamder

private nonisolated enum IntelliJKeymapFiles {
    static let macKeymap = "platform/platform-resources/src/keymaps/Mac OS X 10.5+.xml"
    static let defaultKeymap = "platform/platform-resources/src/keymaps/$default.xml"

    private static let keyAliases = [
        "COMMA": ",",
        "OPEN_BRACKET": "[",
        "CLOSE_BRACKET": "]",
        "SLASH": "/",
        "BACK_SPACE": "backspace",
        "BACK_QUOTE": "`",
        "ENTER": "return",
        "MINUS": "-",
        "EQUALS": "="
    ]

    static func keystrokes(in path: String, convertingControl: Bool) throws -> [String: Set<String>] {
        let document = try XMLDocument(xmlString: try IntelliJTestData.text(path), options: [])
        var result: [String: Set<String>] = [:]
        for node in try document.nodes(forXPath: "//action") {
            guard let action = node as? XMLElement, let id = action.attribute(forName: "id")?.stringValue else {
                continue
            }
            for shortcut in action.elements(forName: "keyboard-shortcut") {
                guard shortcut.attribute(forName: "second-keystroke") == nil,
                      let first = shortcut.attribute(forName: "first-keystroke")?.stringValue,
                      let converted = text(from: first, convertingControl: convertingControl) else { continue }
                result[id, default: []].insert(converted)
            }
        }
        return result
    }

    static func hasDoubleShiftGesture(_ actionID: String) throws -> Bool {
        let document = try XMLDocument(xmlString: try IntelliJTestData.text(defaultKeymap), options: [])
        let nodes = try document.nodes(
            forXPath: "//action[@id='\(actionID)']/keyboard-gesture-shortcut[@keystroke='shift SHIFT'][@modifier='dblClick']"
        )
        return !nodes.isEmpty
    }

    static func text(from keystroke: String, convertingControl: Bool) -> String? {
        let tokens = keystroke.split(separator: " ").map(String.init)
        guard let rawKey = tokens.last else { return nil }
        var modifiers = ShortcutModifiers()
        for token in tokens.dropLast() {
            switch token.lowercased() {
            case "meta": modifiers.insert(.command)
            case "alt": modifiers.insert(.option)
            case "shift": modifiers.insert(.shift)
            case "control", "ctrl": modifiers.insert(convertingControl ? .command : .control)
            default: return nil
            }
        }
        let key = keyAliases[rawKey.uppercased()] ?? rawKey.lowercased()
        return KeyStroke(text: (modifiers.names + [key]).joined(separator: " "))?.text
    }
}

@Suite
struct KeymapCommandTests {
    private static let table: [KeymapCommand: [String]] = [
        .settings: ["command ,"],
        .newDocument: ["command n"],
        .openDocument: ["command o"],
        .closeTab: ["command w"],
        .closeEditor: ["control shift command w"],
        .closeWindow: ["shift command w"],
        .closeWorkspace: ["control option command w"],
        .closeTerminal: ["option command backspace"],
        .save: ["command s"],
        .toolWindowProject: ["command 1"],
        .toolWindowCommit: ["command 0"],
        .toolWindowStructure: ["command 7"],
        .toolWindowFind: ["command 3"],
        .toolWindowRun: ["command 4"],
        .toolWindowProblems: ["command 6"],
        .toolWindowGit: ["command 9"],
        .toolWindowLanguageServices: ["control command l"],
        .toolWindowTerminal: ["option f12"],
        .hideAllToolWindows: ["shift command f12"],
        .maximizeBottomToolWindow: ["shift command '"],
        .gotoNextSplitter: ["option tab"],
        .gotoPreviousSplitter: ["option shift tab"],
        .commandPalette: ["shift command p"],
        .resetFontSize: ["control command 0"],
        .toggleToolbar: ["option command t"],
        .toggleInterface: ["shift command h"],
        .toggleInlayHints: ["control option shift h"],
        .find: ["command f"],
        .findAndReplace: ["command r"],
        .findNext: ["command g"],
        .findPrevious: ["shift command g"],
        .useSelectionForFind: ["option command e"],
        .jumpToSelection: ["command j"],
        .findInFiles: ["shift command f"],
        .replaceInFiles: ["shift command r"],
        .searchEverywhere: ["double shift"],
        .goToFile: ["shift command o"],
        .goToSymbol: ["option command o"],
        .goToLine: ["command l"],
        .findAction: ["shift command a"],
        .recentFiles: ["command e"],
        .goToDeclaration: ["command b"],
        .goToTypeDeclaration: ["shift command b"],
        .showUsages: ["option command f7"],
        .findUsages: ["option f7"],
        .revealInProjectNavigator: ["shift command j"],
        .previousTab: ["shift command ["],
        .nextTab: ["shift command ]"],
        .goBack: ["command ["],
        .goForward: ["command ]"],
        .goToImplementation: ["option command b"],
        .recentLocations: ["shift command e"],
        .fileStructure: ["command f12"],
        .nextProblem: ["option command down"],
        .previousProblem: ["option command up"],
        .moveLineUp: ["option shift up"],
        .moveLineDown: ["option shift down"],
        .quickDocumentation: ["control j", "f1"],
        .extendSelection: ["option up"],
        .shrinkSelection: ["option down"],
        .selectNextOccurrence: ["control g"],
        .unselectOccurrence: ["control shift g"],
        .selectAllOccurrences: ["control command g"],
        .cloneCaretAbove: ["control shift up"],
        .cloneCaretBelow: ["control shift down"],
        .joinLines: ["control shift j"],
        .duplicateLine: ["command d"],
        .deleteLine: ["command backspace"],
        .commentLine: ["command /"],
        .commentBlock: ["option command /"],
        .reformatCode: ["option command l"],
        .renameSymbol: ["shift f6"],
        .showContextActions: ["option return"],
        .optimizeImports: ["control option o"],
        .parameterInfo: ["command p"],
        .collapseCodeBlock: ["command -"],
        .expandCodeBlock: ["command ="],
        .collapseAll: ["shift command -"],
        .expandAll: ["shift command ="],
        .markdownBold: ["control b"],
        .markdownItalic: ["control i"],
        .markdownStrikethrough: ["control shift s"],
        .markdownCodeSpan: ["control shift c"],
        .markdownCreateLink: ["control shift u"],
        .runTask: ["control r"],
        .stopTask: ["command f2"],
        .gitBranches: ["control shift `"],
        .gitCommit: ["command k"],
        .gitPush: ["shift command k"],
        .gitUpdateProject: ["command t"],
        .gitNewBranch: ["option command n"],
        .gitPull: ["option command x"],
        .windowWelcome: ["shift command 1"],
        .windowAbout: ["shift command 2"]
    ]

    private static let intelliJActions: [KeymapCommand: String] = [
        .settings: "ShowSettings",
        .closeTab: "CloseContent",
        .toolWindowProject: "ActivateProjectToolWindow",
        .toolWindowFind: "ActivateFindToolWindow",
        .toolWindowRun: "ActivateRunToolWindow",
        .toolWindowProblems: "ActivateProblemsViewToolWindow",
        .toolWindowStructure: "ActivateStructureToolWindow",
        .toolWindowGit: "ActivateVersionControlToolWindow",
        .toolWindowCommit: "ActivateCommitToolWindow",
        .gotoNextSplitter: "NextSplitter",
        .gotoPreviousSplitter: "PrevSplitter",
        .find: "Find",
        .findNext: "FindNext",
        .findPrevious: "FindPrevious",
        .findInFiles: "FindInPath",
        .replaceInFiles: "ReplaceInPath",
        .goToFile: "GotoFile",
        .goToSymbol: "GotoSymbol",
        .goToLine: "GotoLine",
        .goToDeclaration: "GotoDeclaration",
        .goToTypeDeclaration: "GotoTypeDeclaration",
        .previousTab: "PreviousTab",
        .nextTab: "NextTab",
        .goBack: "Back",
        .goForward: "Forward",
        .quickDocumentation: "QuickJavaDoc",
        .extendSelection: "EditorSelectWord",
        .shrinkSelection: "EditorUnSelectWord",
        .selectNextOccurrence: "SelectNextOccurrence",
        .deleteLine: "EditorDeleteLine",
        .commentBlock: "CommentByBlockComment",
        .runTask: "Run",
        .optimizeImports: "OptimizeImports",
        .goToImplementation: "GotoImplementation",
        .recentLocations: "RecentLocations",
        .fileStructure: "FileStructurePopup",
        .parameterInfo: "ParameterInfo",
        .collapseCodeBlock: "CollapseRegion",
        .expandCodeBlock: "ExpandRegion",
        .collapseAll: "CollapseAllRegions",
        .expandAll: "ExpandAllRegions",
        .findUsages: "FindUsages",
        .showUsages: "ShowUsages",
        .reformatCode: "ReformatCode",
        .recentFiles: "RecentFiles",
        .duplicateLine: "EditorDuplicate",
        .commentLine: "CommentByLineComment",
        .joinLines: "EditorJoinLines",
        .unselectOccurrence: "UnselectPreviousOccurrence",
        .selectAllOccurrences: "SelectAllOccurrences",
        .moveLineUp: "MoveLineUp",
        .moveLineDown: "MoveLineDown",
        .renameSymbol: "RenameElement",
        .stopTask: "Stop",
        .showContextActions: "ShowIntentionActions"
    ]

    @Test
    func everyCommandHasAUniqueIdentifierAndAnInformativeTitle() {
        let commands = KeymapCommand.allCases

        #expect(Set(commands.map(\.id)).count == commands.count)
        #expect(commands.allSatisfy { !$0.title.isEmpty })
        #expect(commands.allSatisfy { KeymapCommand(rawValue: $0.id) == $0 })
        #expect(KeymapCommand(rawValue: "missing") == nil)
    }

    @Test
    func everyGroupHoldsCommandsAndIsTitledLikeIntelliJsTree() {
        for group in KeymapGroup.allCases {
            #expect(KeymapCommand.allCases.contains { $0.group == group })
            #expect(!group.path.isEmpty)
        }
        #expect(KeymapGroup.editorActions.title == "Editor Actions")
        #expect(KeymapGroup.file.title == "Main Menu \u{25B8} File")
        #expect(KeymapGroup.toolWindows.title == "Tool Windows")
        #expect(Set(KeymapGroup.allCases.map(\.title)).count == KeymapGroup.allCases.count)
    }

    @Test
    func defaultsMatchTheTable() {
        for command in KeymapCommand.allCases {
            let expected = Self.table[command] ?? []
            #expect(command.defaultShortcuts.map(\.text) == expected, "\(command.id)")
        }
        #expect(Self.table.keys.allSatisfy { KeymapCommand.allCases.contains($0) })
    }

    @Test
    func defaultsContainNoConflicts() {
        let assignments = KeymapCommand.allCases.flatMap { command in
            command.defaultShortcuts.map { (shortcut: $0, command: command) }
        }
        let byShortcut = Dictionary(grouping: assignments, by: \.shortcut)

        #expect(byShortcut.values.allSatisfy { $0.count == 1 })
    }

    @Test
    func intelliJDefaultsComeFromTheMacOSKeymapAndItsParent() throws {
        let mac = try IntelliJKeymapFiles.keystrokes(in: IntelliJKeymapFiles.macKeymap, convertingControl: false)
        let parent = try IntelliJKeymapFiles.keystrokes(in: IntelliJKeymapFiles.defaultKeymap, convertingControl: true)

        for (command, actionID) in Self.intelliJActions {
            let intelliJ = mac[actionID] ?? parent[actionID] ?? []
            let ours = Set(command.defaultShortcuts.compactMap(\.keyStroke).map(\.text))
            #expect(!ours.isEmpty, "\(command.id)")
            #expect(ours.isSubset(of: intelliJ), "\(command.id) vs \(actionID): \(intelliJ)")
        }
    }

    @Test
    func searchEverywhereIsTheDoubleShiftGesture() throws {
        #expect(try IntelliJKeymapFiles.hasDoubleShiftGesture("SearchEverywhere"))
        #expect(KeymapCommand.searchEverywhere.defaultShortcuts == [.doubleModifier(.shift)])
    }

    @Test
    func intelliJKeystrokeConversionHandlesTheXMLVocabulary() {
        #expect(IntelliJKeymapFiles.text(from: "meta OPEN_BRACKET", convertingControl: false) == "command [")
        #expect(IntelliJKeymapFiles.text(from: "meta shift CLOSE_BRACKET", convertingControl: false) == "shift command ]")
        #expect(IntelliJKeymapFiles.text(from: "control alt L", convertingControl: true) == "option command l")
        #expect(IntelliJKeymapFiles.text(from: "ctrl G", convertingControl: false) == "control g")
        #expect(IntelliJKeymapFiles.text(from: "meta BACK_SPACE", convertingControl: false) == "command backspace")
        #expect(IntelliJKeymapFiles.text(from: "alt ENTER", convertingControl: false) == "option return")
        #expect(IntelliJKeymapFiles.text(from: "meta COMMA", convertingControl: false) == "command ,")
        #expect(IntelliJKeymapFiles.text(from: "hyper B", convertingControl: false) == nil)
        #expect(IntelliJKeymapFiles.text(from: "", convertingControl: false) == nil)
    }

    @Test
    func theBundledJSONEqualsTheRegistry() throws {
        let url = try #require(Bundle.main.url(forResource: "default_keybindings.json", withExtension: nil))
        let stored = try JSONDecoder().decode([KeymapDefaultsEntry].self, from: Data(contentsOf: url))

        #expect(stored == KeymapDefaultsExport.entries)
        #expect(stored.count == KeymapCommand.allCases.count)
    }

    @Test
    func regeneratedJSONRoundTripsTheRegistry() throws {
        let data = try KeymapDefaultsExport.json()
        let decoded = try JSONDecoder().decode([KeymapDefaultsEntry].self, from: data)
        let text = String(decoding: data, as: UTF8.self)

        #expect(decoded == KeymapDefaultsExport.entries)
        #expect(text.contains("Go to Line/Column..."))
        #expect(!text.contains("\\/"))
    }

    @Test
    func exportedEntriesCarryTheShortcutTextsOfEachCommand() throws {
        let quickDoc = try #require(KeymapDefaultsExport.entries.first { $0.id == "editor.quickDocumentation" })

        #expect(quickDoc.title == "Quick Documentation")
        #expect(quickDoc.group == "Main Menu \u{25B8} Editor")
        #expect(quickDoc.shortcuts == ["control j", "f1"])
    }

    @MainActor
    @Test
    func markdownMenuItemsMapOnePerCommandWithMatchingTitles() {
        let commands = MarkdownMenuItem.allCases.map(\.command)

        #expect(Set(commands).count == MarkdownMenuItem.allCases.count)
        #expect(commands.allSatisfy { $0.group == .markdown })
        #expect(KeymapCommand.allCases.filter { $0.group == .markdown }.count == commands.count)
        for item in MarkdownMenuItem.allCases {
            #expect(item.command.title == item.title)
        }
    }
}
