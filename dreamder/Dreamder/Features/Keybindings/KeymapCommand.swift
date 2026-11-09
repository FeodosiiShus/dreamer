nonisolated enum KeymapGroup: CaseIterable, Hashable, Sendable {
    case editorActions
    case app
    case file
    case view
    case find
    case navigate
    case editor
    case markdown
    case tasks
    case git
    case window
    case toolWindows

    var path: [String] {
        switch self {
        case .editorActions: ["Editor Actions"]
        case .app: ["Main Menu", "Dreamder"]
        case .file: ["Main Menu", "File"]
        case .view: ["Main Menu", "View"]
        case .find: ["Main Menu", "Find"]
        case .navigate: ["Main Menu", "Navigate"]
        case .editor: ["Main Menu", "Editor"]
        case .markdown: ["Main Menu", "Markdown"]
        case .tasks: ["Main Menu", "Tasks"]
        case .git: ["Main Menu", "Git"]
        case .window: ["Main Menu", "Window"]
        case .toolWindows: ["Tool Windows"]
        }
    }

    var title: String {
        path.joined(separator: " \u{25B8} ")
    }
}

nonisolated enum KeymapCommand: String, CaseIterable, Hashable, Identifiable, Sendable {
    case about = "app.about"
    case settings = "app.settings"

    case newDocument = "file.new"
    case openDocument = "file.open"
    case closeTab = "file.closeTab"
    case closeEditor = "file.closeEditor"
    case closeWindow = "file.closeWindow"
    case closeWorkspace = "file.closeWorkspace"
    case closeTerminal = "file.closeTerminal"
    case workspaceSettings = "file.workspaceSettings"
    case save = "file.save"

    case toolWindowProject = "toolWindow.project"
    case toolWindowCommit = "toolWindow.commit"
    case toolWindowStructure = "toolWindow.structure"
    case toolWindowFind = "toolWindow.find"
    case toolWindowRun = "toolWindow.run"
    case toolWindowProblems = "toolWindow.problems"
    case toolWindowGit = "toolWindow.git"
    case toolWindowLanguageServices = "toolWindow.languageServices"
    case toolWindowTerminal = "toolWindow.terminal"
    case hideAllToolWindows = "toolWindow.hideAll"
    case maximizeBottomToolWindow = "toolWindow.maximizeBottom"

    case splitRight = "view.splitRight"
    case splitDown = "view.splitDown"
    case unsplit = "view.unsplit"
    case unsplitAll = "view.unsplitAll"
    case changeSplitterOrientation = "view.changeSplitterOrientation"
    case gotoNextSplitter = "view.gotoNextSplitter"
    case gotoPreviousSplitter = "view.gotoPreviousSplitter"
    case commandPalette = "view.commandPalette"
    case increaseFontSize = "view.increaseFontSize"
    case decreaseFontSize = "view.decreaseFontSize"
    case resetFontSize = "view.resetFontSize"
    case toggleToolbar = "view.toggleToolbar"
    case toggleInterface = "view.toggleInterface"
    case dimEditorsWithoutFocus = "view.dimEditorsWithoutFocus"
    case chooseBackgroundImage = "view.chooseBackgroundImage"
    case clearBackgroundImage = "view.clearBackgroundImage"
    case toggleInlayHints = "view.toggleInlayHints"

    case find = "find.find"
    case findAndReplace = "find.findAndReplace"
    case findNext = "find.findNext"
    case findPrevious = "find.findPrevious"
    case useSelectionForFind = "find.useSelectionForFind"
    case jumpToSelection = "find.jumpToSelection"
    case findInFiles = "find.findInFiles"
    case replaceInFiles = "find.replaceInFiles"

    case searchEverywhere = "navigate.searchEverywhere"
    case goToClass = "navigate.goToClass"
    case goToFile = "navigate.goToFile"
    case goToSymbol = "navigate.goToSymbol"
    case goToLine = "navigate.goToLine"
    case findAction = "navigate.findAction"
    case recentFiles = "navigate.recentFiles"
    case goToDeclaration = "navigate.goToDeclaration"
    case goToTypeDeclaration = "navigate.goToTypeDeclaration"
    case showUsages = "navigate.showUsages"
    case findUsages = "navigate.findUsages"
    case revealInProjectNavigator = "navigate.revealInProjectNavigator"
    case previousTab = "navigate.previousTab"
    case nextTab = "navigate.nextTab"
    case goBack = "navigate.back"
    case goForward = "navigate.forward"
    case goToImplementation = "navigate.goToImplementation"
    case recentLocations = "navigate.recentLocations"
    case fileStructure = "navigate.fileStructure"
    case nextProblem = "problems.nextProblem"
    case previousProblem = "problems.previousProblem"

    case moveLineUp = "editor.moveLineUp"
    case moveLineDown = "editor.moveLineDown"
    case quickDocumentation = "editor.quickDocumentation"

    case extendSelection = "editorActions.extendSelection"
    case shrinkSelection = "editorActions.shrinkSelection"
    case selectNextOccurrence = "editorActions.selectNextOccurrence"
    case unselectOccurrence = "editorActions.unselectOccurrence"
    case selectAllOccurrences = "editorActions.selectAllOccurrences"
    case cloneCaretAbove = "editorActions.cloneCaretAbove"
    case cloneCaretBelow = "editorActions.cloneCaretBelow"
    case joinLines = "editorActions.joinLines"
    case indentSelection = "editorActions.indentSelection"
    case unindentSelection = "editorActions.unindentSelection"
    case duplicateLine = "editorActions.duplicateLine"
    case deleteLine = "editorActions.deleteLine"
    case commentLine = "editorActions.commentLine"
    case commentBlock = "editorActions.commentBlock"
    case reformatCode = "editorActions.reformatCode"
    case renameSymbol = "editorActions.renameSymbol"
    case toggleSoftWraps = "editorActions.toggleSoftWraps"
    case showContextActions = "editorActions.showContextActions"
    case optimizeImports = "editorActions.optimizeImports"
    case parameterInfo = "editorActions.parameterInfo"
    case collapseCodeBlock = "editorActions.collapseCodeBlock"
    case expandCodeBlock = "editorActions.expandCodeBlock"
    case collapseAll = "editorActions.collapseAll"
    case expandAll = "editorActions.expandAll"
    case collapseComments = "editorActions.collapseComments"

    case markdownBold = "markdown.bold"
    case markdownItalic = "markdown.italic"
    case markdownStrikethrough = "markdown.strikethrough"
    case markdownCodeSpan = "markdown.codeSpan"
    case markdownCreateLink = "markdown.createLink"
    case markdownHeaderNormal = "markdown.headerNormal"
    case markdownHeaderTitle = "markdown.headerTitle"
    case markdownHeaderSubtitle = "markdown.headerSubtitle"
    case markdownHeading3 = "markdown.heading3"
    case markdownHeading4 = "markdown.heading4"
    case markdownHeading5 = "markdown.heading5"
    case markdownHeading6 = "markdown.heading6"
    case markdownHeaderUp = "markdown.headerUp"
    case markdownHeaderDown = "markdown.headerDown"
    case markdownInsertTable = "markdown.insertTable"
    case markdownFormatTable = "markdown.formatTable"
    case markdownGenerateTableOfContents = "markdown.generateTableOfContents"

    case runTask = "tasks.run"
    case stopTask = "tasks.stop"
    case showTaskOutput = "tasks.showOutput"
    case manageTasks = "tasks.manage"

    case gitBranches = "git.branches"
    case gitResolveConflicts = "git.resolveConflicts"
    case gitCommit = "git.commit"
    case gitPush = "git.push"
    case gitUpdateProject = "git.updateProject"
    case gitFetch = "git.fetch"
    case gitNewBranch = "git.newBranch"
    case gitPull = "git.pull"
    case gitFetchChanges = "git.fetchChanges"
    case gitStageAll = "git.stageAll"
    case gitUnstageAll = "git.unstageAll"
    case gitStash = "git.stash"
    case gitDiscardAll = "git.discardAll"
    case gitAddRemote = "git.addRemote"

    case windowWelcome = "window.welcome"
    case windowAbout = "window.about"

    var id: String { rawValue }

    var title: String { entry.title }

    var group: KeymapGroup { entry.group }

    var defaultShortcuts: [Shortcut] { entry.defaults }

    private typealias Entry = (title: String, group: KeymapGroup, defaults: [Shortcut])

    private var entry: Entry { // swiftlint:disable:this function_body_length cyclomatic_complexity
        switch self {
        case .about: ("About Dreamder", .app, [])
        case .settings: ("Settings...", .app, [.stroke(",", .command)])

        case .newDocument: ("New", .file, [.stroke("n", .command)])
        case .openDocument: ("Open...", .file, [.stroke("o", .command)])
        case .closeTab: ("Close Tab", .file, [.stroke("w", .command)])
        case .closeEditor: ("Close Editor", .file, [.stroke("w", [.control, .shift, .command])])
        case .closeWindow: ("Close Window", .file, [.stroke("w", [.shift, .command])])
        case .closeWorkspace: ("Close Workspace", .file, [.stroke("w", [.control, .option, .command])])
        case .closeTerminal: ("Close Terminal", .file, [.stroke(KeyNames.backspace, [.option, .command])])
        case .workspaceSettings: ("Workspace Settings", .file, [])
        case .save: ("Save", .file, [.stroke("s", .command)])

        case .toolWindowProject: ("Project", .toolWindows, [.stroke("1", .command)])
        case .toolWindowCommit: ("Commit", .toolWindows, [.stroke("0", .command)])
        case .toolWindowStructure: ("Structure", .toolWindows, [.stroke("7", .command)])
        case .toolWindowFind: ("Find", .toolWindows, [.stroke("3", .command)])
        case .toolWindowRun: ("Run", .toolWindows, [.stroke("4", .command)])
        case .toolWindowProblems: ("Problems", .toolWindows, [.stroke("6", .command)])
        case .toolWindowGit: ("Git", .toolWindows, [.stroke("9", .command)])
        case .toolWindowLanguageServices: ("Language Services", .toolWindows, [.stroke("l", [.control, .command])])
        case .toolWindowTerminal: ("Terminal", .toolWindows, [.stroke(KeyNames.f12, .option)])
        case .hideAllToolWindows:
            ("Hide All Tool Windows", .toolWindows, [.stroke(KeyNames.f12, [.shift, .command])])
        case .maximizeBottomToolWindow:
            ("Maximize Bottom Tool Window", .toolWindows, [.stroke("'", [.shift, .command])])

        case .splitRight: ("Split Right", .view, [])
        case .splitDown: ("Split Down", .view, [])
        case .unsplit: ("Unsplit", .view, [])
        case .unsplitAll: ("Unsplit All", .view, [])
        case .changeSplitterOrientation: ("Change Splitter Orientation", .view, [])
        case .gotoNextSplitter: ("Go to Next Splitter", .view, [.stroke(KeyNames.tab, .option)])
        case .gotoPreviousSplitter: ("Go to Previous Splitter", .view, [.stroke(KeyNames.tab, [.option, .shift])])
        case .commandPalette: ("Show Command Palette", .view, [.stroke("p", [.shift, .command])])
        case .increaseFontSize: ("Increase Font Size", .view, [])
        case .decreaseFontSize: ("Decrease Font Size", .view, [])
        case .resetFontSize: ("Reset Font Size", .view, [.stroke("0", [.control, .command])])
        case .toggleToolbar: ("Toggle Toolbar", .view, [.stroke("t", [.option, .command])])
        case .toggleInterface: ("Toggle Interface", .view, [.stroke("h", [.shift, .command])])
        case .dimEditorsWithoutFocus: ("Dim Editors Without Focus", .view, [])
        case .chooseBackgroundImage: ("Choose Background Image...", .view, [])
        case .clearBackgroundImage: ("Clear Background Image", .view, [])
        case .toggleInlayHints: ("Toggle Inlay Hints", .view, [.stroke("h", [.control, .option, .shift])])

        case .find: ("Find...", .find, [.stroke("f", .command)])
        case .findAndReplace: ("Find and Replace...", .find, [.stroke("r", .command)])
        case .findNext: ("Find Next", .find, [.stroke("g", .command)])
        case .findPrevious: ("Find Previous", .find, [.stroke("g", [.shift, .command])])
        case .useSelectionForFind: ("Use Selection for Find", .find, [.stroke("e", [.option, .command])])
        case .jumpToSelection: ("Jump to Selection", .find, [.stroke("j", .command)])
        case .findInFiles: ("Find in Files...", .find, [.stroke("f", [.shift, .command])])
        case .replaceInFiles: ("Replace in Files...", .find, [.stroke("r", [.shift, .command])])

        case .searchEverywhere: ("Search Everywhere", .navigate, [.doubleModifier(.shift)])
        case .goToClass: ("Go to Class...", .navigate, [])
        case .goToFile: ("Go to File...", .navigate, [.stroke("o", [.shift, .command])])
        case .goToSymbol: ("Go to Symbol...", .navigate, [.stroke("o", [.option, .command])])
        case .goToLine: ("Go to Line/Column...", .navigate, [.stroke("l", .command)])
        case .findAction: ("Find Action...", .navigate, [.stroke("a", [.shift, .command])])
        case .recentFiles: ("Recent Files", .navigate, [.stroke("e", .command)])
        case .goToDeclaration: ("Go to Declaration or Usages", .navigate, [.stroke("b", .command)])
        case .goToTypeDeclaration: ("Go to Type Declaration", .navigate, [.stroke("b", [.shift, .command])])
        case .showUsages: ("Show Usages", .navigate, [.stroke(KeyNames.f7, [.option, .command])])
        case .findUsages: ("Find Usages", .navigate, [.stroke(KeyNames.f7, .option)])
        case .revealInProjectNavigator:
            ("Reveal in Project Navigator", .navigate, [.stroke("j", [.shift, .command])])
        case .previousTab: ("Show Previous Tab", .navigate, [.stroke("[", [.shift, .command])])
        case .nextTab: ("Show Next Tab", .navigate, [.stroke("]", [.shift, .command])])
        case .goBack: ("Go Back", .navigate, [.stroke("[", .command)])
        case .goForward: ("Go Forward", .navigate, [.stroke("]", .command)])
        case .goToImplementation: ("Go to Implementation", .navigate, [.stroke("b", [.option, .command])])
        case .recentLocations: ("Recent Locations", .navigate, [.stroke("e", [.shift, .command])])
        case .fileStructure: ("File Structure", .navigate, [.stroke(KeyNames.f12, .command)])
        case .nextProblem: ("Next Problem", .navigate, [.stroke(KeyNames.down, [.option, .command])])
        case .previousProblem: ("Previous Problem", .navigate, [.stroke(KeyNames.up, [.option, .command])])

        case .moveLineUp: ("Move Line Up", .editor, [.stroke(KeyNames.up, [.option, .shift])])
        case .moveLineDown: ("Move Line Down", .editor, [.stroke(KeyNames.down, [.option, .shift])])
        case .quickDocumentation: ("Quick Documentation", .editor, [.stroke("j", .control), .stroke(KeyNames.f1)])

        case .extendSelection: ("Extend Selection", .editorActions, [.stroke(KeyNames.up, .option)])
        case .shrinkSelection: ("Shrink Selection", .editorActions, [.stroke(KeyNames.down, .option)])
        case .selectNextOccurrence: ("Add Selection for Next Occurrence", .editorActions, [.stroke("g", .control)])
        case .unselectOccurrence: ("Unselect Occurrence", .editorActions, [.stroke("g", [.control, .shift])])
        case .selectAllOccurrences: ("Select All Occurrences", .editorActions, [.stroke("g", [.control, .command])])
        case .cloneCaretAbove: ("Clone Caret Above", .editorActions, [.stroke(KeyNames.up, [.control, .shift])])
        case .cloneCaretBelow: ("Clone Caret Below", .editorActions, [.stroke(KeyNames.down, [.control, .shift])])
        case .joinLines: ("Join Lines", .editorActions, [.stroke("j", [.control, .shift])])
        case .indentSelection: ("Indent Selection", .editorActions, [])
        case .unindentSelection: ("Unindent Selection", .editorActions, [])
        case .duplicateLine: ("Duplicate Line or Selection", .editorActions, [.stroke("d", .command)])
        case .deleteLine: ("Delete Line", .editorActions, [.stroke(KeyNames.backspace, .command)])
        case .commentLine: ("Comment with Line Comment", .editorActions, [.stroke("/", .command)])
        case .commentBlock: ("Comment with Block Comment", .editorActions, [.stroke("/", [.option, .command])])
        case .reformatCode: ("Reformat Code", .editorActions, [.stroke("l", [.option, .command])])
        case .renameSymbol: ("Rename...", .editorActions, [.stroke(KeyNames.f6, .shift)])
        case .toggleSoftWraps: ("Toggle Soft Wraps", .editorActions, [])
        case .showContextActions: ("Show Context Actions", .editorActions, [.stroke(KeyNames.enter, .option)])
        case .optimizeImports: ("Optimize Imports", .editorActions, [.stroke("o", [.control, .option])])
        case .parameterInfo: ("Parameter Info", .editorActions, [.stroke("p", .command)])
        case .collapseCodeBlock: ("Collapse", .editorActions, [.stroke("-", .command)])
        case .expandCodeBlock: ("Expand", .editorActions, [.stroke("=", .command)])
        case .collapseAll: ("Collapse All", .editorActions, [.stroke("-", [.shift, .command])])
        case .expandAll: ("Expand All", .editorActions, [.stroke("=", [.shift, .command])])
        case .collapseComments: ("Collapse Comments", .editorActions, [])

        case .markdownBold: ("Bold", .markdown, [.stroke("b", .control)])
        case .markdownItalic: ("Italic", .markdown, [.stroke("i", .control)])
        case .markdownStrikethrough: ("Strikethrough", .markdown, [.stroke("s", [.control, .shift])])
        case .markdownCodeSpan: ("Code Span", .markdown, [.stroke("c", [.control, .shift])])
        case .markdownCreateLink: ("Create Link", .markdown, [.stroke("u", [.control, .shift])])
        case .markdownHeaderNormal: ("Normal", .markdown, [])
        case .markdownHeaderTitle: ("Title", .markdown, [])
        case .markdownHeaderSubtitle: ("Subtitle", .markdown, [])
        case .markdownHeading3: ("Heading 3", .markdown, [])
        case .markdownHeading4: ("Heading 4", .markdown, [])
        case .markdownHeading5: ("Heading 5", .markdown, [])
        case .markdownHeading6: ("Heading 6", .markdown, [])
        case .markdownHeaderUp: ("Header Up", .markdown, [])
        case .markdownHeaderDown: ("Header Down", .markdown, [])
        case .markdownInsertTable: ("Insert Table\u{2026}", .markdown, [])
        case .markdownFormatTable: ("Format Table", .markdown, [])
        case .markdownGenerateTableOfContents: ("Generate Table of Contents", .markdown, [])

        case .runTask: ("Run Selected Task", .tasks, [.stroke("r", .control)])
        case .stopTask: ("Stop Selected Task", .tasks, [.stroke(KeyNames.f2, .command)])
        case .showTaskOutput: ("Show Selected Task Output", .tasks, [])
        case .manageTasks: ("Manage Tasks...", .tasks, [])

        case .gitBranches: ("Branches\u{2026}", .git, [.stroke("`", [.control, .shift])])
        case .gitResolveConflicts: ("Resolve Conflicts\u{2026}", .git, [])
        case .gitCommit: ("Commit\u{2026}", .git, [.stroke("k", .command)])
        case .gitPush: ("Push\u{2026}", .git, [.stroke("k", [.command, .shift])])
        case .gitUpdateProject: ("Update Project\u{2026}", .git, [.stroke("t", .command)])
        case .gitFetch: ("Fetch", .git, [])
        case .gitNewBranch: ("New Branch\u{2026}", .git, [.stroke("n", [.command, .option])])
        case .gitPull: ("Pull\u{2026}", .git, [.stroke("x", [.command, .option])])
        case .gitFetchChanges: ("Fetch Changes\u{2026}", .git, [])
        case .gitStageAll: ("Stage All Changes", .git, [])
        case .gitUnstageAll: ("Unstage All Changes", .git, [])
        case .gitStash: ("Stash Changes\u{2026}", .git, [])
        case .gitDiscardAll: ("Discard All Changes\u{2026}", .git, [])
        case .gitAddRemote: ("Add Existing Remote\u{2026}", .git, [])

        case .windowWelcome: ("Welcome to Dreamder", .window, [.stroke("1", [.shift, .command])])
        case .windowAbout: ("About Dreamder", .window, [.stroke("2", [.shift, .command])])
        }
    }
}
