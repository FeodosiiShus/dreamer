import AppKit

nonisolated enum SearchEverywhereSectionKind: String, CaseIterable {
    case recent
    case files
    case classes
    case symbols
    case actions
    case text

    var title: String {
        switch self {
        case .recent: return "Recent Files"
        case .files: return "Files"
        case .classes: return "Classes"
        case .symbols: return "Symbols"
        case .actions: return "Actions"
        case .text: return "Text"
        }
    }
}

enum SearchEverywhereTab: String, CaseIterable, Identifiable {
    case all
    case classes
    case files
    case symbols
    case actions
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .classes: return "Classes"
        case .files: return "Files"
        case .symbols: return "Symbols"
        case .actions: return "Actions"
        case .text: return "Text"
        }
    }

    var position: Int {
        switch self {
        case .all: return 0
        case .classes: return 1
        case .files: return 2
        case .symbols: return 3
        case .actions: return 4
        case .text: return 5
        }
    }

    func cycled(by delta: Int) -> SearchEverywhereTab {
        let tabs = Self.allCases
        let count = tabs.count
        return tabs[((position + delta) % count + count) % count]
    }

    var sections: [SearchEverywhereSectionKind] {
        switch self {
        case .all: return [.recent, .files, .classes, .symbols, .actions, .text]
        case .classes: return [.classes]
        case .files: return [.recent, .files]
        case .symbols: return [.symbols]
        case .actions: return [.actions]
        case .text: return [.text]
        }
    }
}

enum SearchEverywhereItemKind: String, Hashable {
    case file
    case classSymbol
    case symbol
    case action
    case text
}

enum SearchEverywhereMode: Hashable {
    case everywhere
    case recentFiles
}

@MainActor
final class SearchEverywhereAction {
    let identity: String
    let path: String
    let shortcut: String
    let selector: String
    private let performBlock: @MainActor () -> Void

    init(
        identity: String,
        path: String,
        shortcut: String,
        selector: String = "",
        perform: @escaping @MainActor () -> Void
    ) {
        self.identity = identity
        self.path = path
        self.shortcut = shortcut
        self.selector = selector
        self.performBlock = perform
    }

    func perform() {
        performBlock()
    }

    var title: String {
        path.components(separatedBy: " | ").reduce(path) { _, component in component }
    }

    var menuPath: String {
        let components = path.components(separatedBy: " | ").dropLast()
        guard !components.isEmpty else { return "" }
        let joined = components.joined(separator: " | ")
        return joined == "Command" ? "" : joined
    }

    var equalityKey: String {
        selector.isEmpty ? "action:\(identity)" : "action:\(selector)|\(title)"
    }
}

struct SearchEverywhereItem: Identifiable {
    let id: String
    let section: SearchEverywhereSectionKind
    let kind: SearchEverywhereItemKind
    let title: String
    let detail: String
    let iconName: String
    let ranges: [NSRange]
    let url: URL?
    let line: Int?
    let column: Int?
    let action: SearchEverywhereAction?
    let weight: SearchEverywhereComposedWeight
    let isExactMatch: Bool
    let equalityKey: String?

    var rankingCandidate: SearchEverywhereCandidate {
        SearchEverywhereCandidate(
            id: id,
            provider: section.provider,
            title: title,
            weight: weight,
            isExactMatch: isExactMatch,
            equalityKey: equalityKey
        )
    }
}

extension SearchEverywhereItem: Hashable {
    static func == (lhs: SearchEverywhereItem, rhs: SearchEverywhereItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct SearchEverywhereSection: Identifiable {
    let kind: SearchEverywhereSectionKind
    let items: [SearchEverywhereItem]

    var id: String { kind.rawValue }
}

@MainActor
enum SearchEverywhereActionProvider {
    static func actions() -> [SearchEverywhereAction] {
        actions(mainMenu: NSApp.mainMenu)
    }

    static func actions(
        mainMenu: NSMenu?,
        commands: [Command] = CommandManager.shared.commands
    ) -> [SearchEverywhereAction] {
        var collected: [SearchEverywhereAction] = []
        guard let mainMenu else { return collected }

        for topLevelItem in mainMenu.items {
            guard let submenu = topLevelItem.submenu else { continue }
            let prefix = topLevelItem.title.isEmpty ? [submenu.title] : [topLevelItem.title]
            collectActions(from: submenu, prefix: prefix, into: &collected)
        }

        for command in commands {
            collected.append(SearchEverywhereAction(
                identity: "command:\(command.id)",
                path: "Command | \(command.title)",
                shortcut: "",
                perform: { command.closureWrapper() }
            ))
        }

        return collected
    }

    static func shortcutString(for item: NSMenuItem) -> String {
        let key = item.keyEquivalent
        guard let scalar = key.unicodeScalars.first else { return "" }

        var result = ""
        let modifiers = item.keyEquivalentModifierMask
        if modifiers.contains(.control) { result += "\u{2303}" }
        if modifiers.contains(.option) { result += "\u{2325}" }
        if modifiers.contains(.shift) { result += "\u{21E7}" }
        if modifiers.contains(.command) { result += "\u{2318}" }
        result += displayKey(key, firstScalar: scalar)
        return result
    }

    private static func collectActions(
        from menu: NSMenu,
        prefix: [String],
        into collected: inout [SearchEverywhereAction]
    ) {
        for item in menu.items {
            if item.isSeparatorItem || item.isHidden { continue }
            let title = item.title
            guard !title.isEmpty else { continue }

            if let submenu = item.submenu {
                collectActions(from: submenu, prefix: prefix + [title], into: &collected)
                continue
            }

            guard let action = item.action, item.isEnabled else { continue }

            let path = (prefix + [title]).joined(separator: " | ")
            let shortcut = shortcutString(for: item)
            let capturedMenu = menu
            let capturedItem = item
            collected.append(SearchEverywhereAction(
                identity: "menu:\(path)",
                path: path,
                shortcut: shortcut,
                selector: NSStringFromSelector(action),
                perform: {
                    if let index = capturedMenu.items.firstIndex(where: { $0 === capturedItem }) {
                        capturedMenu.performActionForItem(at: index)
                    } else {
                        NSApp.sendAction(action, to: capturedItem.target, from: capturedItem)
                    }
                }
            ))
        }
    }

    private static let specialKeySymbols: [String: String] = [
        "\r": "\u{21A9}",
        "\u{3}": "\u{21A9}",
        "\t": "\u{21E5}",
        "\u{8}": "\u{232B}",
        "\u{7F}": "\u{232B}",
        "\u{1B}": "\u{238B}",
        " ": "\u{2423}",
        "\u{F700}": "\u{2191}",
        "\u{F701}": "\u{2193}",
        "\u{F702}": "\u{2190}",
        "\u{F703}": "\u{2192}",
        "\u{F72C}": "\u{21DE}",
        "\u{F72D}": "\u{21DF}",
        "\u{F729}": "\u{2196}",
        "\u{F72B}": "\u{2198}"
    ]

    private static func displayKey(_ key: String, firstScalar scalar: Unicode.Scalar) -> String {
        if let symbol = specialKeySymbols[key] {
            return symbol
        }

        let value = scalar.value
        if (0xF704...0xF726).contains(value) {
            return "F\(value - 0xF704 + 1)"
        }
        return key.uppercased()
    }
}
