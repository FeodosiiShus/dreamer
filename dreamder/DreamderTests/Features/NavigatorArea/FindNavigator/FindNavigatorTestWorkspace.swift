import AppKit
import Testing
@testable import Dreamder

@MainActor
enum FindNavigatorTestWorkspace {
    static let replaceMode: [SearchModeModel] = [.Replace, .Text, .Containing]

    static func writeProject(in dir: URL) throws {
        try "let needle = 1\nlet other = needle + 2\n"
            .write(to: dir.appending(path: "a.swift"), atomically: true, encoding: .utf8)
        try "needle here\n"
            .write(to: dir.appending(path: "b.txt"), atomically: true, encoding: .utf8)
    }

    static func searched(in dir: URL, query: String = "needle") async throws -> WorkspaceDocument {
        try writeProject(in: dir)
        let workspace = try HostedViewFixture.makeWorkspace(in: dir)
        let state = try #require(workspace.searchState)
        try await eventually { state.indexStatus == .done }
        await state.search(query)
        try await eventually { state.findNavigatorStatus == .found }
        return workspace
    }

    static func searchedForReplace(
        in dir: URL,
        query: String = "needle",
        replacement: String = "pin"
    ) async throws -> WorkspaceDocument {
        try writeProject(in: dir)
        let workspace = try HostedViewFixture.makeWorkspace(in: dir)
        let state = try #require(workspace.searchState)
        try await eventually { state.indexStatus == .done }
        state.selectedMode = replaceMode
        state.replaceText = replacement
        await state.search(query)
        try await eventually { state.findNavigatorStatus == .found }
        return workspace
    }
}

@MainActor
enum FindNavigatorKeyEvents {
    static let returnKeyCode: UInt16 = 36
    static let enterKeyCode: UInt16 = 76
    static let deleteKeyCode: UInt16 = 51

    static func make(
        _ type: NSEvent.EventType,
        keyCode: UInt16,
        characters: String,
        modifiers: NSEvent.ModifierFlags = [],
        in window: NSWindow
    ) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    static func returnKey(
        keyCode: UInt16 = FindNavigatorKeyEvents.returnKeyCode,
        modifiers: NSEvent.ModifierFlags = [],
        in window: NSWindow
    ) throws -> NSEvent {
        try make(.keyDown, keyCode: keyCode, characters: "\r", modifiers: modifiers, in: window)
    }

    static func deleteKeyUp(in window: NSWindow) throws -> NSEvent {
        try make(
            .keyUp,
            keyCode: deleteKeyCode,
            characters: String(NSEvent.SpecialKey.delete.unicodeScalar),
            in: window
        )
    }
}

@MainActor
final class FindNavigatorListHarness {
    let workspace: WorkspaceDocument
    let controller: FindNavigatorListViewController
    let window: NSWindow
    let outline: FindOutlineView
    let fileA: SearchResultModel
    let fileB: SearchResultModel

    init(workspace: WorkspaceDocument) throws {
        let state = try #require(workspace.searchState)
        self.workspace = workspace
        self.fileA = try #require(state.searchResult.first(where: { $0.file.name == "a.swift" }))
        self.fileB = try #require(state.searchResult.first(where: { $0.file.name == "b.txt" }))
        let controller = FindNavigatorListViewController(workspace: workspace)
        self.controller = controller
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.orderFront(nil)
        self.window = window
        let scrollView = try #require(controller.view as? NSScrollView)
        self.outline = try #require(scrollView.documentView as? FindOutlineView)
    }

    var ordered: [SearchResultModel] {
        [fileA, fileB]
    }

    var editor: Editor? {
        workspace.editorManager?.activeEditor
    }

    func load() {
        controller.updateNewSearchResults(ordered)
    }

    func select(_ item: Any) {
        outline.selectRowIndexes(IndexSet(integer: outline.row(forItem: item)), byExtendingSelection: false)
    }

    func selectionChanged() {
        controller.outlineViewSelectionDidChange(
            Notification(name: NSOutlineView.selectionDidChangeNotification, object: outline)
        )
    }

    func close() {
        window.close()
        workspace.close()
    }
}

extension Array {
    nonisolated func required(at index: Int) throws -> Element {
        try #require(indices.contains(index) ? self[index] : nil)
    }
}
