import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
private final class MenuTarget: NSObject {
    var invocations: [String] = []

    @objc func openDocument(_ sender: Any?) {
        invocations.append("open")
    }

    @objc func clearRecents(_ sender: Any?) {
        invocations.append("clear")
    }
}

@MainActor
@Suite(.uiGate)
struct SearchEverywhereActionProviderTests {
    @MainActor
    private struct Menus {
        let target = MenuTarget()
        let mainMenu = NSMenu(title: "Main")
        let recentMenu = NSMenu(title: "Open Recent")
        let clearItem: NSMenuItem

        init() {
            mainMenu.autoenablesItems = false
            recentMenu.autoenablesItems = false
            clearItem = NSMenuItem(title: "Clear Menu", action: #selector(MenuTarget.clearRecents(_:)), keyEquivalent: "")
            clearItem.target = target
            recentMenu.addItem(clearItem)

            let file = NSMenu(title: "File")
            file.autoenablesItems = false
            let open = NSMenuItem(title: "Open\u{2026}", action: #selector(MenuTarget.openDocument(_:)), keyEquivalent: "o")
            open.keyEquivalentModifierMask = .command
            open.target = target
            file.addItem(open)
            file.addItem(.separator())

            let hidden = NSMenuItem(title: "Hidden", action: #selector(MenuTarget.openDocument(_:)), keyEquivalent: "")
            hidden.target = target
            hidden.isHidden = true
            file.addItem(hidden)

            let untitled = NSMenuItem(title: "", action: #selector(MenuTarget.openDocument(_:)), keyEquivalent: "")
            untitled.target = target
            file.addItem(untitled)

            let disabled = NSMenuItem(title: "Disabled", action: #selector(MenuTarget.openDocument(_:)), keyEquivalent: "")
            disabled.target = target
            disabled.isEnabled = false
            file.addItem(disabled)

            let inert = NSMenuItem(title: "Inert", action: nil, keyEquivalent: "")
            file.addItem(inert)

            let recent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
            recent.submenu = recentMenu
            file.addItem(recent)

            let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
            fileItem.submenu = file
            mainMenu.addItem(fileItem)

            let edit = NSMenu(title: "Edit")
            edit.autoenablesItems = false
            let undo = NSMenuItem(title: "Undo", action: #selector(MenuTarget.openDocument(_:)), keyEquivalent: "z")
            undo.keyEquivalentModifierMask = [.command, .shift]
            undo.target = target
            edit.addItem(undo)
            let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
            editItem.submenu = edit
            mainMenu.addItem(editItem)
            mainMenu.addItem(NSMenuItem(title: "Plain", action: nil, keyEquivalent: ""))
        }
    }

    private func menuActions(_ menus: Menus) -> [SearchEverywhereAction] {
        SearchEverywhereActionProvider.actions(mainMenu: menus.mainMenu).filter { $0.identity.hasPrefix("menu:") }
    }

    @Test
    func menusAreFlattenedIntoPathsSkippingSeparatorsHiddenDisabledAndInertItems() throws {
        let menus = Menus()

        let actions = menuActions(menus)

        #expect(actions.map(\.path) == ["File | Open\u{2026}", "File | Open Recent | Clear Menu", "Edit | Undo"])
        #expect(actions.map(\.shortcut) == ["\u{2318}O", "", "\u{21E7}\u{2318}Z"])
        #expect(actions.map(\.title) == ["Open\u{2026}", "Clear Menu", "Undo"])
        #expect(actions.map(\.menuPath) == ["File", "File | Open Recent", "Edit"])
        #expect(SearchEverywhereActionProvider.actions(mainMenu: nil).filter { $0.identity.hasPrefix("menu:") }.isEmpty)
    }

    @Test
    func performingAnActionRunsTheMenuItemsAction() throws {
        let menus = Menus()
        let actions = menuActions(menus)
        let open = try #require(actions.first)

        open.perform()
        open.perform()

        #expect(menus.target.invocations == ["open", "open"])
    }

    @Test
    func performingAnActionWhoseItemLeftTheMenuStillSendsTheAction() throws {
        let menus = Menus()
        let clear = try #require(menuActions(menus).first { $0.title == "Clear Menu" })
        menus.recentMenu.removeItem(menus.clearItem)

        clear.perform()

        #expect(menus.target.invocations == ["clear"])
    }

    @Test
    func shortcutStringsUseMacSymbolsInModifierOrder() {
        func shortcut(_ key: String, _ modifiers: NSEvent.ModifierFlags = []) -> String {
            let item = NSMenuItem(title: "Item", action: nil, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            return SearchEverywhereActionProvider.shortcutString(for: item)
        }

        #expect(shortcut("") == "")
        #expect(shortcut("a", [.control, .option, .shift, .command]) == "\u{2303}\u{2325}\u{21E7}\u{2318}A")
        #expect(shortcut("\r", .command) == "\u{2318}\u{21A9}")
        #expect(shortcut("\t") == "\u{21E5}")
        #expect(shortcut("\u{8}") == "\u{232B}")
        #expect(shortcut("\u{1B}") == "\u{238B}")
        #expect(shortcut(" ") == "\u{2423}")
        #expect(shortcut("\u{F700}") == "\u{2191}")
        #expect(shortcut("\u{F701}") == "\u{2193}")
        #expect(shortcut("\u{F702}") == "\u{2190}")
        #expect(shortcut("\u{F703}") == "\u{2192}")
        #expect(shortcut("\u{F72C}") == "\u{21DE}")
        #expect(shortcut("\u{F72D}") == "\u{21DF}")
        #expect(shortcut("\u{F729}") == "\u{2196}")
        #expect(shortcut("\u{F72B}") == "\u{2198}")
        #expect(shortcut("\u{F704}") == "F1")
        #expect(shortcut("\u{F707}", .command) == "\u{2318}F4")
        #expect(shortcut("\u{F726}") == "F35")
        #expect(shortcut("\u{F727}") == "\u{F727}")
    }

    @Test
    func itemsAreEqualAndHashedByTheirIdentifier() {
        let first = SearchEverywhereFixtures.item(id: "file:same", title: "One")
        let sameID = SearchEverywhereFixtures.item(id: "file:same", title: "Two")
        let other = SearchEverywhereFixtures.item(id: "file:other", title: "One")

        #expect(first == sameID)
        #expect(first != other)
        #expect(Set([first, sameID, other]).count == 2)
        #expect(first.hashValue == sameID.hashValue)
    }

    @Test
    func sectionKindsAndTabsHaveTheirDisplayTitles() {
        #expect(
            SearchEverywhereSectionKind.allCases.map(\.title)
                == ["Recent Files", "Files", "Classes", "Symbols", "Actions", "Text"]
        )
        #expect(
            SearchEverywhereTab.allCases.map(\.title)
                == ["All", "Classes", "Files", "Symbols", "Actions", "Text"]
        )
    }

    @Test
    func tabsKnowTheirPositionAndCycleInBothDirectionsAcrossTheEnds() {
        for (index, tab) in SearchEverywhereTab.allCases.enumerated() {
            #expect(tab.position == index)
            #expect(tab.cycled(by: 0) == tab)
        }

        #expect(SearchEverywhereTab.all.cycled(by: -1) == .text)
        #expect(SearchEverywhereTab.text.cycled(by: 1) == .all)
        #expect(SearchEverywhereTab.files.cycled(by: -8) == .all)
        #expect(SearchEverywhereTab.classes.cycled(by: 2) == .symbols)
    }

    @Test
    func anActionTitleIsTheLastMenuPathComponent() {
        #expect(SearchEverywhereFixtures.action("File | Open Recent | Clear Menu").title == "Clear Menu")
        #expect(SearchEverywhereFixtures.action("File | Open Recent | Clear Menu").menuPath == "File | Open Recent")
    }

    @Test
    func anActionWithoutAMenuSeparatorIsItsOwnTitleAndHasNoMenuPath() {
        let action = SearchEverywhereFixtures.action("Standalone")

        #expect(action.title == "Standalone")
        #expect(action.menuPath.isEmpty)
    }

    @Test
    func aTopLevelMenuItemWithoutATitleFallsBackToItsSubmenuTitle() throws {
        let target = MenuTarget()
        let tools = NSMenu(title: "Tools")
        tools.autoenablesItems = false
        let run = NSMenuItem(title: "Run", action: #selector(MenuTarget.openDocument(_:)), keyEquivalent: "")
        run.target = target
        tools.addItem(run)
        let mainMenu = NSMenu(title: "Main")
        mainMenu.autoenablesItems = false
        let top = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        top.submenu = tools
        top.title = ""
        mainMenu.addItem(top)

        let actions = SearchEverywhereActionProvider.actions(mainMenu: mainMenu, commands: [])

        let action = try #require(actions.first)
        #expect(actions.count == 1)
        #expect(action.path == "Tools | Run")
        action.perform()
        #expect(target.invocations == ["open"])
    }

    @Test
    func registeredCommandsAreListedUnderTheCommandPrefixAndPerformTheirClosure() throws {
        let target = MenuTarget()
        let commands = [
            Command(id: "toggle-thing", title: "Toggle Thing", closureWrapper: { target.invocations.append("command") })
        ]

        let actions = SearchEverywhereActionProvider.actions(mainMenu: NSMenu(title: "Main"), commands: commands)

        let action = try #require(actions.first)
        #expect(actions.count == 1)
        #expect(action.identity == "command:toggle-thing")
        #expect(action.path == "Command | Toggle Thing")
        #expect(action.title == "Toggle Thing")
        #expect(action.menuPath.isEmpty)
        action.perform()
        #expect(target.invocations == ["command"])
    }
}
