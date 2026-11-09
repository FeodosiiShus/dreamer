import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
enum SearchEverywhereFixtures {
    static func makeWorkspace(_ dir: URL) throws -> WorkspaceDocument {
        try touch(dir, "Sources/AppDelegate.swift", "import Foundation\n\nclass AppDelegate {\n    func launchApp() {}\n}\n")
        try touch(dir, "Sources/Helpers/StringUtils.swift", "struct StringUtils {\n    func trimmedValue() -> String { \"\" }\n}\n")
        try touch(dir, "README.md", "Intro\nfind the needle here\n")
        let workspace = WorkspaceDocument()
        try workspace.read(from: dir, ofType: "")
        return workspace
    }

    static func openTab(_ name: String, in workspace: WorkspaceDocument, dir: URL) throws {
        let file = try #require(workspace.workspaceFileManager?.getFile(
            dir.appending(path: name).path(percentEncoded: false),
            createIfNotFound: true
        ))
        let editorManager = try #require(workspace.editorManager)
        editorManager.openTab(item: file)
    }

    static func keyEvent(_ keyCode: UInt16, flags: NSEvent.ModifierFlags = [], windowNumber: Int = 0) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    static func action(
        _ path: String,
        shortcut: String = "",
        perform: @escaping @MainActor () -> Void = {}
    ) -> SearchEverywhereAction {
        SearchEverywhereAction(identity: "test:\(path)", path: path, shortcut: shortcut, perform: perform)
    }

    static func item(
        id: String = "file:a.swift",
        kind: SearchEverywhereItemKind = .file,
        title: String = "a.swift",
        detail: String = "Sources",
        ranges: [NSRange] = [],
        action: SearchEverywhereAction? = nil
    ) -> SearchEverywhereItem {
        SearchEverywhereItem(
            id: id,
            section: kind == .action ? .actions : .files,
            kind: kind,
            title: title,
            detail: detail,
            iconName: "general/runAnything",
            ranges: ranges,
            url: nil,
            line: nil,
            column: nil,
            action: action,
            weight: SearchEverywhereComposedWeight(0),
            isExactMatch: false,
            equalityKey: nil
        )
    }

    static func preview(targetLine: Int = 2) -> SearchEverywherePreview {
        SearchEverywherePreview(
            url: URL(fileURLWithPath: "/tmp/Preview.swift"),
            title: "Preview.swift",
            subtitle: "Sources",
            lines: [
                SearchEverywherePreview.Line(number: 1, text: "import Foundation", isTarget: targetLine == 1),
                SearchEverywherePreview.Line(number: 2, text: "", isTarget: targetLine == 2),
                SearchEverywherePreview.Line(number: 3, text: "struct Preview {}", isTarget: targetLine == 3)
            ]
        )
    }
}

@MainActor
final class SearchEverywhereCallRecorder {
    private(set) var selectedItems: [String] = []
    private(set) var selectedTabs: [SearchEverywhereTab] = []
    private(set) var events: [String] = []

    func select(_ item: SearchEverywhereItem) {
        selectedItems.append(item.id)
        events.append("select")
    }

    func open() {
        events.append("open")
    }

    func selectTab(_ tab: SearchEverywhereTab) {
        selectedTabs.append(tab)
    }
}
