import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct CommandsFixesACoverageTests {
    private func withSwizzledMenuItems(_ body: () -> Void) {
        let probe = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        probe.keyEquivalentModifierMask = [.command]
        let installedHere = !probe.isHidden
        if installedHere {
            NSMenuItem.swizzle()
        }
        defer {
            if installedHere {
                NSMenuItem.swizzle()
            }
        }
        body()
    }

    @Test
    func hiddenModifierIsTheNumericPadFlag() {
        #expect(EventModifiers.hidden == .numericPad)
    }

    @Test
    func numericPadModifierMarksTheItemAsAlternate() {
        withSwizzledMenuItems {
            let item = NSMenuItem(title: "Alternate Item", action: nil, keyEquivalent: "a")

            item.keyEquivalentModifierMask = [.option, .numericPad]

            #expect(item.isAlternate)
            #expect(item.isHidden == false)
        }
    }

    @Test
    func plainModifierLeavesTheItemUntouched() {
        withSwizzledMenuItems {
            let item = NSMenuItem(title: "Plain Item", action: nil, keyEquivalent: "p")

            item.keyEquivalentModifierMask = [.command, .shift]

            #expect(item.isAlternate == false)
            #expect(item.isHidden == false)
            #expect(item.keyEquivalentModifierMask == [.command, .shift])
        }
    }

    @Test
    func itemsWithoutATitleAreHiddenButKeepTheirKeyEquivalent() {
        withSwizzledMenuItems {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "h")

            item.keyEquivalentModifierMask = [.command]

            #expect(item.isHidden)
            #expect(item.allowsKeyEquivalentWhenHidden)
        }
    }

    @Test
    func openWindowActionItemsAreHidden() {
        withSwizzledMenuItems {
            let item = NSMenuItem(title: "OpenWindowAction", action: nil, keyEquivalent: "")

            item.keyEquivalentModifierMask = [.command]

            #expect(item.isHidden)
            #expect(item.allowsKeyEquivalentWhenHidden)
        }
    }

    @Test
    func openRecentItemReceivesTheRecentProjectsSubmenu() {
        withSwizzledMenuItems {
            let item = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")

            item.keyEquivalentModifierMask = [.command]

            #expect(item.submenu != nil)
        }
    }

    @Test
    func recentSubmenuMovesToTheLatestOpenRecentItemInsteadOfRaising() {
        withSwizzledMenuItems {
            let first = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
            first.keyEquivalentModifierMask = [.command]
            let second = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
            second.keyEquivalentModifierMask = [.command]

            #expect(first.submenu == nil)
            #expect(second.submenu === FileCommands.recentProjectsMenu.makeMenu())
        }
    }

    @Test
    func reapplyingModifiersToTheSameOpenRecentItemKeepsItsSubmenu() {
        withSwizzledMenuItems {
            let item = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")

            item.keyEquivalentModifierMask = [.command]
            item.keyEquivalentModifierMask = [.option, .numericPad]

            #expect(item.submenu === FileCommands.recentProjectsMenu.makeMenu())
            #expect(item.isAlternate)
        }
    }

    @Test
    func attachingTheMenuToASecondItemDetachesItFromTheFirst() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let recentMenu = RecentProjectsMenu(manager: RecentProjectsManager(defaults: defaults), open: { _ in })
        let first = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let second = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let host = NSMenu(title: "Host")
        host.addItem(first)
        host.addItem(second)

        recentMenu.attachMenu(to: first)
        recentMenu.attachMenu(to: first)
        recentMenu.attachMenu(to: second)

        #expect(first.submenu == nil)
        #expect(second.submenu === recentMenu.makeMenu())
        withExtendedLifetime(host) {}
    }
}
