import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class FindPickerSelectionRecorder {
    var selected: [SearchModeModel] = []
}

@Observable
@MainActor
private final class FindPickerMenuItemHolder {
    var item: NSMenuItem

    init(item: NSMenuItem) {
        self.item = item
    }
}

@MainActor
private struct FindPickerPopupHarness: View {
    let holder: FindPickerMenuItemHolder
    let popup: NSPopUpButton

    var body: some View {
        FindModePicker.NSPopUpButtonView<NSMenuItem>(
            selection: Bindable(holder).item,
            isOn: holder.item.title == "First"
        ) { popup }
    }
}

@MainActor
@Suite(.uiGate)
struct FindModePickerTests {
    private func hostPicker(
        _ workspace: WorkspaceDocument,
        modes: [SearchModeModel] = SearchModeModel.SearchModes,
        selection: SearchModeModel = .Find,
        isLastItem: Bool = false,
        isHovering: Bool = false,
        activeState: ControlActiveState = .key,
        colorScheme: ColorScheme = .dark,
        recorder: FindPickerSelectionRecorder
    ) throws -> HostedView {
        try HostedViewFixture.hostInWorkspace(workspace) {
            FindModePicker(
                modes: modes,
                selection: .constant(selection),
                onSelect: { recorder.selected.append($0) },
                isLastItem: isLastItem,
                isHovering: isHovering
            )
            .environment(\.controlActiveState, activeState)
            .environment(\.colorScheme, colorScheme)
        }
    }

    @Test
    func rendersEveryHoverActivityAndSchemeVariant() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let recorder = FindPickerSelectionRecorder()

            let idle = try hostPicker(workspace, recorder: recorder)
            defer { idle.close() }
            try await idle.settle()
            #expect(idle.renders())
            let idleShot = idle.snapshot()

            let hovering = try hostPicker(workspace, isHovering: true, recorder: recorder)
            defer { hovering.close() }
            try await hovering.settle()
            #expect(HostedView.pixelsDiffer(idleShot, hovering.snapshot()))

            let last = try hostPicker(workspace, isLastItem: true, recorder: recorder)
            defer { last.close() }
            try await last.settle()
            #expect(HostedView.pixelsDiffer(idleShot, last.snapshot()))

            let inactiveLight = try hostPicker(
                workspace,
                activeState: .inactive,
                colorScheme: .light,
                recorder: recorder
            )
            defer { inactiveLight.close() }
            try await inactiveLight.settle()
            #expect(inactiveLight.renders())

            let selectedSecond = try hostPicker(workspace, selection: .Replace, recorder: recorder)
            defer { selectedSecond.close() }
            try await selectedSecond.settle()
            #expect(selectedSecond.renders())
        }
    }

    @Test
    func popupListsTheModesAndSelectingAnItemCallsOnSelect() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let recorder = FindPickerSelectionRecorder()
            let hosted = try hostPicker(workspace, selection: .Replace, recorder: recorder)
            defer { hosted.close() }
            try await hosted.settle()

            let popup = try #require(hosted.views(of: NSPopUpButton.self).first)
            #expect(popup.menu?.items.map(\.title) == ["Find", "Replace"])
            #expect(popup.titleOfSelectedItem == "Replace")
            #expect(popup.menu is FindModeMenu)

            popup.menu?.performActionForItem(at: 0)
            popup.menu?.performActionForItem(at: 1)
            #expect(recorder.selected == [.Find, .Replace])
        }
    }

    @Test
    func unmatchedSelectionLeavesTheFirstItemSelected() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let recorder = FindPickerSelectionRecorder()
            let hosted = try hostPicker(workspace, selection: .References, recorder: recorder)
            defer { hosted.close() }
            try await hosted.settle()
            let popup = try #require(hosted.views(of: NSPopUpButton.self).first)
            #expect(popup.titleOfSelectedItem == "Find")
        }
    }

    @Test
    func hoverAndTapHandlersAreSafeWithoutAPopupButton() async throws {
        try withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let picker = FindModePicker(
                modes: SearchModeModel.SearchModes,
                selection: .constant(.Find),
                onSelect: { _ in },
                isLastItem: true
            )
            picker.setHovering(true)
            picker.setHovering(false)
            picker.openMenu()
            #expect(picker.modes == SearchModeModel.SearchModes)
        }
    }

    @Test
    func popupViewFollowsTheBindingAndPublishesMenuActions() async throws {
        let first = NSMenuItem(title: "First", action: nil, keyEquivalent: "")
        let second = NSMenuItem(title: "Second", action: nil, keyEquivalent: "")
        first.representedObject = first
        second.representedObject = second
        let menu = NSMenu()
        menu.addItem(first)
        menu.addItem(second)
        let popup = NSPopUpButton()
        popup.menu = menu
        let holder = FindPickerMenuItemHolder(item: second)

        let hosted = HostedViewFixture.host {
            FindPickerPopupHarness(holder: holder, popup: popup)
        }
        defer { hosted.close() }
        try await hosted.settle()
        #expect(popup.titleOfSelectedItem == "Second")

        NotificationCenter.default.post(
            name: NSMenu.didSendActionNotification,
            object: menu,
            userInfo: ["MenuItem": first]
        )
        #expect(holder.item === first)
        try await hosted.settle()
        #expect(popup.titleOfSelectedItem == "First")

        NotificationCenter.default.post(name: NSMenu.didSendActionNotification, object: menu, userInfo: nil)
        #expect(holder.item === first)
    }

    @Test
    func popupViewWithoutAMatchingItemKeepsTheCurrentSelection() async throws {
        let only = NSMenuItem(title: "Only", action: nil, keyEquivalent: "")
        let stranger = NSMenuItem(title: "Stranger", action: nil, keyEquivalent: "")
        let menu = NSMenu()
        menu.addItem(only)
        let popup = NSPopUpButton()
        popup.menu = menu
        let holder = FindPickerMenuItemHolder(item: stranger)

        let hosted = HostedViewFixture.host {
            FindModePicker.NSPopUpButtonView<NSMenuItem>(selection: Bindable(holder).item, isOn: false) { popup }
        }
        defer { hosted.close() }
        try await hosted.settle()
        #expect(popup.titleOfSelectedItem == "Only")
    }

    @Test
    func menuItemInvokesItsHandlerDirectly() {
        let recorder = FindPickerSelectionRecorder()
        let item = FindModeMenuItem(mode: .Replace, onSelect: { recorder.selected.append($0) })
        #expect(item.title == "Replace")
        #expect(item.representedObject as? SearchModeModel == .Replace)
        item.handleSelect()
        #expect(recorder.selected == [.Replace])
    }

    @Test
    func menuAndItemSurviveKeyedArchiving() throws {
        let menu = FindModeMenu(modes: [], onSelect: { _ in })
        let menuData = try NSKeyedArchiver.archivedData(withRootObject: menu, requiringSecureCoding: false)
        let menuUnarchiver = try NSKeyedUnarchiver(forReadingFrom: menuData)
        menuUnarchiver.requiresSecureCoding = false
        let decodedMenu = menuUnarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
        menuUnarchiver.finishDecoding()
        #expect(decodedMenu is FindModeMenu)

        let item = FindModeMenuItem(mode: .Find, onSelect: { _ in })
        item.target = nil
        item.representedObject = nil
        let itemData = try NSKeyedArchiver.archivedData(withRootObject: item, requiringSecureCoding: false)
        let itemUnarchiver = try NSKeyedUnarchiver(forReadingFrom: itemData)
        itemUnarchiver.requiresSecureCoding = false
        let decodedItem = itemUnarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
        itemUnarchiver.finishDecoding()
        #expect(decodedItem is FindModeMenuItem)
    }
}
