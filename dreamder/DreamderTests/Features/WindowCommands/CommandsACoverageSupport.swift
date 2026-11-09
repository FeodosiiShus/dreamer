import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
final class CommandsACoverageMenu {
    let menu: NSMenu

    init(menu: NSMenu) {
        self.menu = menu
    }

    var items: [NSMenuItem] {
        menu.update()
        return menu.items.filter { !$0.isSeparatorItem }
    }

    var titles: [String] {
        items.map(\.title)
    }

    var enabledStates: [Bool] {
        items.map(\.isEnabled)
    }

    var keyEquivalents: [String] {
        items.map(\.keyEquivalent)
    }

    func item(titled title: String) -> NSMenuItem? {
        items.first { $0.title == title }
    }

    func click(_ index: Int) throws {
        let all = items
        let item = try #require(all.indices.contains(index) ? all[index] : nil)
        press(item)
    }

    func click(titled title: String) throws {
        press(try #require(item(titled: title)))
    }

    func close() {
        menu.removeAllItems()
    }

    private func press(_ item: NSMenuItem) {
        guard item.isEnabled else { return }
        let index = menu.index(of: item)
        guard index >= 0 else { return }
        menu.performActionForItem(at: index)
    }
}

@MainActor
enum CommandsACoverageSupport {
    static func host<Content: View>(@ViewBuilder _ content: () -> Content) -> CommandsACoverageMenu {
        CommandsACoverageMenu(menu: NSHostingMenu(rootView: content()))
    }
}

@MainActor
final class CommandsACoverageRecorder: NSResponder {
    private(set) var received: [String] = []
    private(set) var findTags: [Int] = []

    @objc func showQuickDocumentation(_ sender: Any?) {
        received.append(#function)
    }

    @objc func openWorkspaceSettings(_ sender: Any?) {
        received.append(#function)
    }

    @objc
    func trustProject(_ sender: Any?) {
        received.append(#function)
    }

    @objc func saveDocument(_ sender: Any?) {
        received.append(#function)
    }

    @objc func openCommandPalette(_ sender: Any?) {
        received.append(#function)
    }

    @objc func closeCurrentTab(_ sender: Any?) {
        received.append(#function)
    }

    @objc func closeActiveEditor(_ sender: Any?) {
        received.append(#function)
    }

    @objc override func centerSelectionInVisibleArea(_ sender: Any?) {
        received.append(#function)
    }

    @objc func performFindPanelAction(_ sender: Any?) {
        findTags.append((sender as? NSMenuItem)?.tag ?? -1)
    }
}

@MainActor
final class CommandsACoverageWindow: NSWindow {
    private(set) var performCloseCalls = 0

    override func performClose(_ sender: Any?) {
        performCloseCalls += 1
    }

    static func make() -> CommandsACoverageWindow {
        let window = CommandsACoverageWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        return window
    }
}
