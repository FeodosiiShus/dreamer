import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized)
struct SearchEverywhereViewModelTests {
    private func makeWorkspace(_ dir: URL) throws -> WorkspaceDocument {
        try FileManager.default.createDirectory(at: dir.appending(path: "Sources/Helpers"), withIntermediateDirectories: true)
        try "import Foundation\n\nclass AppDelegate {\n    func launchApp() {}\n}\n"
            .write(to: dir.appending(path: "Sources/AppDelegate.swift"), atomically: true, encoding: .utf8)
        try "struct StringUtils {\n    func trimmedValue() -> String { \"\" }\n}\n"
            .write(to: dir.appending(path: "Sources/Helpers/StringUtils.swift"), atomically: true, encoding: .utf8)
        try "Intro\nfind the needle here\n"
            .write(to: dir.appending(path: "README.md"), atomically: true, encoding: .utf8)
        let workspace = WorkspaceDocument()
        try workspace.read(from: dir, ofType: "")
        return workspace
    }

    private func keyEvent(_ keyCode: UInt16, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    @Test
    func filesTabMatchesCamelHumpsAndCarriesLineSuffix() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            let model = SearchEverywhereViewModel(workspace: workspace)
            model.start(on: .files)
            model.query = "strutil:7"
            try await eventually { model.selectedItem?.title == "StringUtils.swift" }

            let item = try #require(model.selectedItem)
            #expect(item.kind == .file)
            #expect(item.detail == "Sources/Helpers")
            #expect(item.line == 7)
            #expect(model.sections.map(\.kind) == [.files])
        }
    }

    @Test
    func classesTabListsOnlyTypesWithTheirLocation() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            let model = SearchEverywhereViewModel(workspace: workspace)
            model.start(on: .classes)
            model.query = "AppDel"
            try await eventually { model.flatItems.contains { $0.title == "AppDelegate" } }

            let item = try #require(model.flatItems.first { $0.title == "AppDelegate" })
            #expect(item.kind == .classSymbol)
            #expect(item.detail == "Sources/AppDelegate.swift:3")
            #expect(model.flatItems.allSatisfy { $0.kind == .classSymbol })
        }
    }

    @Test
    func symbolsTabFindsMethods() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            let model = SearchEverywhereViewModel(workspace: workspace)
            model.start(on: .symbols)
            model.query = "trimmedVal"
            try await eventually { model.flatItems.contains { $0.title == "trimmedValue" } }

            let item = try #require(model.flatItems.first { $0.title == "trimmedValue" })
            #expect(item.line == 2)
            #expect(item.url?.lastPathComponent == "StringUtils.swift")
        }
    }

    @Test
    func textTabFindsLinesInProjectFiles() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            let model = SearchEverywhereViewModel(workspace: workspace)
            model.start(on: .text)
            model.query = "needle"
            try await eventually { !model.flatItems.isEmpty }

            let item = try #require(model.flatItems.first)
            #expect(item.kind == .text)
            #expect(item.detail == "README.md:2")
            #expect(item.title.contains("needle"))
        }
    }

    @Test
    func allTabGroupsSectionsAndPreviewsTheSelection() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            let model = SearchEverywhereViewModel(workspace: workspace)
            model.start(on: .all)
            model.query = "AppDelegate"
            try await eventually {
                let kinds = model.sections.map(\.kind)
                return kinds.contains(.files) && kinds.contains(.classes)
            }

            let kinds = model.sections.map(\.kind)
            let fileIndex = try #require(kinds.firstIndex(of: .files))
            let classIndex = try #require(kinds.firstIndex(of: .classes))
            #expect(classIndex < fileIndex)
            #expect(Set(kinds).count == kinds.count)
            let priorities = model.flatItems.map { $0.section.provider.priority }
            #expect(priorities == priorities.sorted(by: >))
            #expect(model.sections.allSatisfy { $0.items.count <= 8 })
            if model.showsPreview {
                try await eventually { model.preview != nil }
                #expect(model.preview?.url == model.selectedItem?.url)
            }
        }
    }

    @Test
    func keyboardMovesSelectionWithinBoundsAndCyclesTabs() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            let model = SearchEverywhereViewModel(workspace: workspace)
            model.start(on: .files)
            model.query = "s"
            try await eventually { model.flatItems.count >= 2 }
            let count = model.flatItems.count

            #expect(model.handle(event: try keyEvent(125)))
            #expect(model.selection == 1)
            #expect(model.handle(event: try keyEvent(126)))
            #expect(model.handle(event: try keyEvent(126)))
            #expect(model.selection == 0)
            #expect(model.handle(event: try keyEvent(119)))
            #expect(model.selection == count - 1)
            #expect(model.handle(event: try keyEvent(121)))
            #expect(model.selection == count - 1)
            #expect(model.handle(event: try keyEvent(115)))
            #expect(model.selection == 0)

            #expect(model.handle(event: try keyEvent(48)))
            #expect(model.tab == .symbols)
            #expect(model.handle(event: try keyEvent(48, flags: .shift)))
            #expect(model.handle(event: try keyEvent(48, flags: .shift)))
            #expect(model.tab == .classes)
            model.cycleTab(by: -2)
            #expect(model.tab == .text)
            model.cycleTab(by: 1)
            #expect(model.tab == .all)

            #expect(model.handle(event: try keyEvent(0)) == false)
        }
    }

    @Test
    func escapeDismissesAndEnterOpensTheFileAtTheRequestedLine() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            let model = SearchEverywhereViewModel(workspace: workspace)
            var dismissals = 0
            model.dismiss = { dismissals += 1 }
            model.start(on: .files)

            #expect(model.handle(event: try keyEvent(53)))
            #expect(dismissals == 1)

            model.query = "AppDelegate:4:9"
            try await eventually { model.selectedItem?.title == "AppDelegate.swift" && model.selectedItem?.line == 4 }
            #expect(model.selectedItem?.column == 9)
            #expect(model.handle(event: try keyEvent(36)))

            #expect(dismissals == 2)
            let tab = try #require(workspace.editorManager?.activeEditor.selectedTab)
            #expect(tab.file.url.lastPathComponent == "AppDelegate.swift")
            #expect(tab.cursorPositions.first?.start.line == 4)
            #expect(tab.cursorPositions.first?.start.column == 9)
        }
    }

    @Test
    func recentFilesModeIsFilesOnlyWithoutPreview() throws {
        let model = SearchEverywhereViewModel(workspace: nil, mode: .recentFiles)
        model.start(on: .all)
        #expect(model.tab == .files)
        #expect(model.showsPreview == false)
        #expect(model.panelWidth == 560)
        #expect(model.panelHeight == 400)
        #expect(model.flatItems.isEmpty)
        model.selectTab(.classes)
        #expect(model.tab == .files)

        let everywhere = SearchEverywhereViewModel(workspace: nil)
        #expect(everywhere.panelWidth == 670)
        #expect(everywhere.panelHeight == 520)
    }

    @Test
    func emptyResultsKeepSelectionAtZero() async throws {
        try await withTempDir { dir in
            let model = SearchEverywhereViewModel(workspace: try makeWorkspace(dir))
            model.start(on: .files)
            model.query = "zzzzqqq"
            try await Task.sleep(for: .milliseconds(300))
            #expect(model.flatItems.isEmpty)
            #expect(model.selection == 0)
            #expect(model.selectedItem == nil)
            model.moveSelection(by: 5)
            #expect(model.selection == 0)
        }
    }

    @Test
    func menuActionsWithTheSameTitleAndSelectorShareAnEqualityKey() {
        let appMenu = SearchEverywhereAction(
            identity: "menu:Dreamder | About Dreamder",
            path: "Dreamder | About Dreamder",
            shortcut: "",
            selector: "performAction:",
            perform: {}
        )
        let windowMenu = SearchEverywhereAction(
            identity: "menu:Window | About Dreamder",
            path: "Window | About Dreamder",
            shortcut: "",
            selector: "performAction:",
            perform: {}
        )
        let other = SearchEverywhereAction(
            identity: "menu:Window | Zoom",
            path: "Window | Zoom",
            shortcut: "",
            selector: "performAction:",
            perform: {}
        )
        let command = SearchEverywhereAction(identity: "command:about", path: "Command | About Dreamder", shortcut: "", perform: {})

        #expect(appMenu.equalityKey == windowMenu.equalityKey)
        #expect(appMenu.equalityKey != other.equalityKey)
        #expect(command.equalityKey == "action:command:about")
    }
}
