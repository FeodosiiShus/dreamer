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
        path.components(separatedBy: " | ").last ?? path
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

    static func actions(mainMenu: NSMenu?) -> [SearchEverywhereAction] {
        var collected: [SearchEverywhereAction] = []
        guard let mainMenu else { return collected }

        for topLevelItem in mainMenu.items {
            guard let submenu = topLevelItem.submenu else { continue }
            let prefix = topLevelItem.title.isEmpty ? [submenu.title] : [topLevelItem.title]
            collectActions(from: submenu, prefix: prefix, into: &collected)
        }

        for command in CommandManager.shared.commands {
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
        guard !key.isEmpty else { return "" }

        var result = ""
        let modifiers = item.keyEquivalentModifierMask
        if modifiers.contains(.control) { result += "\u{2303}" }
        if modifiers.contains(.option) { result += "\u{2325}" }
        if modifiers.contains(.shift) { result += "\u{21E7}" }
        if modifiers.contains(.command) { result += "\u{2318}" }
        result += displayKey(key)
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

    private static func displayKey(_ key: String) -> String {
        switch key {
        case "\r", "\u{3}": return "\u{21A9}"
        case "\t": return "\u{21E5}"
        case "\u{8}", "\u{7F}": return "\u{232B}"
        case "\u{1B}": return "\u{238B}"
        case " ": return "\u{2423}"
        case "\u{F700}": return "\u{2191}"
        case "\u{F701}": return "\u{2193}"
        case "\u{F702}": return "\u{2190}"
        case "\u{F703}": return "\u{2192}"
        case "\u{F72C}": return "\u{21DE}"
        case "\u{F72D}": return "\u{21DF}"
        case "\u{F729}": return "\u{2196}"
        case "\u{F72B}": return "\u{2198}"
        default: break
        }

        guard let scalar = key.unicodeScalars.first else { return key.uppercased() }
        let value = scalar.value
        if (0xF704...0xF726).contains(value) {
            return "F\(value - 0xF704 + 1)"
        }
        return key.uppercased()
    }
}
