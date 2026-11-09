import AppKit
import CodeEditSourceEditor
import Foundation
import Synchronization
import Testing
@testable import Dreamder

private final class RecentLocationsLoaderCalls: Sendable {
    private let storage = Mutex<[[URL]]>([])

    func record(_ urls: [URL]) {
        storage.withLock { $0.append(urls) }
    }

    var batches: [[URL]] {
        storage.withLock { $0 }
    }
}

@MainActor
private final class RecentLocationsDismissals {
    var restoreFlags: [Bool] = []
}

@MainActor
struct RecentLocationsPopupFixture {
    let directory: URL
    let workspace: WorkspaceDocument
    let tracker: RecentLocationsTracker

    static func make(in directory: URL, names: [String]) throws -> Self {
        for name in names {
            let text = (1...40).map { "\(name) line \($0)" }.joined(separator: "\n")
            try text.write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
        }
        let workspace = try HostedViewFixture.makeWorkspace(in: directory)
        return Self(directory: directory, workspace: workspace, tracker: RecentLocationsStore.shared.history(for: workspace))
    }

    func place(_ name: String, line: Int, column: Int = 1) -> EditorPlace {
        EditorPlace(fileURL: directory.appending(path: name), line: line, column: column)
    }

    func open(_ name: String, line: Int? = nil) throws {
        let file = try #require(workspace.workspaceFileManager?.getFile(
            directory.appending(path: name).path(percentEncoded: false),
            createIfNotFound: true
        ))
        workspace.editorManager?.openTab(item: file)
        if let line {
            workspace.editorManager?.activeEditor.selectedTab?.cursorPositions = [CursorPosition(line: line, column: 1)]
        }
    }

    var selectedName: String? {
        workspace.editorManager?.activeEditor.selectedTab?.file.url.lastPathComponent
    }

    var caretLine: Int? {
        workspace.editorManager?.activeEditor.selectedTab?.cursorPositions.first?.start.line
    }

    func recordBack(_ places: [EditorPlace]) {
        for place in places {
            tracker.recordNavigation(from: place)
        }
    }

    func recordChanges(_ places: [EditorPlace]) {
        for place in places {
            tracker.recordChange(place)
        }
    }
}

func recentLocationsKeyEvent(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try #require(NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifiers,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "",
        charactersIgnoringModifiers: "",
        isARepeat: false,
        keyCode: keyCode
    ))
}

@MainActor
@Suite(.uiGate)
struct RecentLocationsViewModelTests {
    private let instantLoader: RecentLocationsViewModel.TextLoader = { urls in
        Dictionary(uniqueKeysWithValues: urls.map { ($0, "loaded \($0.lastPathComponent)\nsecond line") })
    }

    private func names(_ model: RecentLocationsViewModel) -> [String] {
        model.rows.map(\.fileName)
    }

    @Test
    func rowsListTheNewestPlaceFirst() async throws {
        try withTempDir { directory in
            let fixture = try RecentLocationsPopupFixture.make(in: directory, names: ["a.txt", "b.txt", "c.txt"])
            defer { fixture.workspace.close() }
            fixture.recordBack([fixture.place("a.txt", line: 5), fixture.place("b.txt", line: 10), fixture.place("c.txt", line: 30)])

            let model = RecentLocationsViewModel(tracker: fixture.tracker, workspace: fixture.workspace, loadTexts: instantLoader)

            #expect(names(model) == ["c.txt", "b.txt", "a.txt"])
            #expect(model.rows.map(\.place.line) == [30, 10, 5])
            #expect(model.title == "Recent Locations")
            #expect(model.countText == "(3)")
            #expect(model.selectedRow?.fileName == "c.txt")
            #expect(RecentLocationsViewModel.navigationTitle == "Recent Locations")
            #expect(RecentLocationsViewModel.changedTitle == "Recently Edited Locations")
            #expect(RecentLocationsViewModel.toggleTitle == "Show edited only")
            #expect(RecentLocationsViewModel.toggleShortcut == "\u{21E7}\u{2318}E")
            #expect(RecentLocationsViewModel.emptyText == "No recent locations found")
            #expect(RecentLocationsViewModel.emptyFileText == "Empty lines")
        }
    }

    @Test
    func previewsStartPendingAndFillInWhenTheTextsArrive() async throws {
        try await withTempDir { directory in
            let fixture = try RecentLocationsPopupFixture.make(in: directory, names: ["a.txt"])
            defer { fixture.workspace.close() }
            fixture.recordBack([fixture.place("a.txt", line: 2)])
            let slowLoader: RecentLocationsViewModel.TextLoader = { urls in
                try? await Task.sleep(for: .milliseconds(150))
                return Dictionary(uniqueKeysWithValues: urls.map { ($0, "first\nsecond\nthird") })
            }

            let model = RecentLocationsViewModel(tracker: fixture.tracker, workspace: fixture.workspace, loadTexts: slowLoader)

            #expect(model.rows.map(\.preview) == [.pending])
            try await eventually { model.rows.first?.preview != .pending }
            guard case .lines(let lines)? = model.rows.first?.preview else {
                Issue.record("expected lines")
                return
            }
            #expect(lines.map(\.text) == ["first", "second", "third"])
        }
    }

    @Test
    func theDefaultLoaderReadsFilesFromDisk() async throws {
        try await withTempDir { directory in
            let fixture = try RecentLocationsPopupFixture.make(in: directory, names: ["a.txt"])
            defer { fixture.workspace.close() }
            fixture.recordBack([fixture.place("a.txt", line: 3)])
            let missing = directory.appending(path: "missing.txt")

            let loaded = await RecentLocationsTextLoader.read([directory.appending(path: "a.txt"), missing])
            let model = RecentLocationsViewModel(tracker: fixture.tracker, workspace: fixture.workspace)

            #expect(loaded.keys.map(\.lastPathComponent) == ["a.txt"])
            try await eventually {
                guard case .lines(let lines)? = model.rows.first?.preview else { return false }
                return lines.contains { $0.text == "a.txt line 3" }
            }
        }
    }

    @Test
    func openDocumentsProvideTheirInMemoryText() async throws {
        try withTempDir { directory in
            let fixture = try RecentLocationsPopupFixture.make(in: directory, names: ["a.txt", "b.txt"])
            defer { fixture.workspace.close() }
            try fixture.open("a.txt", line: 1)
            try fixture.open("b.txt", line: 1)
            let storage = try #require(fixture.workspace.editorManager?.activeEditor.tabs.first?.file.fileDocument?.content)
            storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: "in memory\nonly here")
            fixture.recordBack([fixture.place("a.txt", line: 1)])
            let calls = RecentLocationsLoaderCalls()

            let model = RecentLocationsViewModel(
                tracker: fixture.tracker,
                workspace: fixture.workspace,
                loadTexts: { urls in
                    calls.record(urls)
                    return [:]
                }
            )

            guard case .lines(let lines)? = model.rows.first?.preview else {
                Issue.record("expected lines")
                return
            }
            #expect(lines.map(\.text) == ["in memory", "only here"])
            #expect(calls.batches.isEmpty)
        }
    }

    @Test
    func theToggleSwitchesBetweenNavigationAndChangedPlaces() async throws {
        try withTempDir { directory in
            let fixture = try RecentLocationsPopupFixture.make(in: directory, names: ["a.txt", "b.txt", "c.txt"])
            defer { fixture.workspace.close() }
            fixture.recordBack([fixture.place("a.txt", line: 5), fixture.place("b.txt", line: 10)])
            fixture.recordChanges([fixture.place("c.txt", line: 7)])
            let model = RecentLocationsViewModel(tracker: fixture.tracker, workspace: fixture.workspace, loadTexts: instantLoader)
            model.select(1)

            model.showChangedOnly = true

            #expect(names(model) == ["c.txt"])
            #expect(model.title == "Recently Edited Locations")
            #expect(model.countText == "(1)")
            #expect(model.selectedIndex == 0)

            model.showChangedOnly = false
            #expect(names(model) == ["b.txt", "a.txt"])
            #expect(model.title == "Recent Locations")
        }
    }

    @Test
    func startingInChangedModeListsEditedPlaces() async throws {
        try withTempDir { directory in
            let fixture = try RecentLocationsPopupFixture.make(in: directory, names: ["a.txt", "c.txt"])
            defer { fixture.workspace.close() }
            fixture.recordBack([fixture.place("a.txt", line: 5)])
            fixture.recordChanges([fixture.place("c.txt", line: 7)])

            let model = RecentLocationsViewModel(
                tracker: fixture.tracker,
                workspace: fixture.workspace,
                showChangedOnly: true,
                loadTexts: instantLoader
            )

            #expect(names(model) == ["c.txt"])
        }
    }

    @Test
    func missingFilesAreDroppedWhenThePopupOpens() async throws {
        try withTempDir { directory in
            let fixture = try RecentLocationsPopupFixture.make(in: directory, names: ["a.txt", "b.txt"])
            defer { fixture.workspace.close() }
            fixture.recordBack([fixture.place("a.txt", line: 5), fixture.place("b.txt", line: 10)])
            try FileManager.default.removeItem(at: directory.appending(path: "a.txt"))

            let model = RecentLocationsViewModel(tracker: fixture.tracker, workspace: fixture.workspace, loadTexts: instantLoader)

            #expect(names(model) == ["b.txt"])
        }
    }

    @Test
    func selectionMovesAndWraps() async throws {
        try withTempDir { directory in
            let fixture = try RecentLocationsPopupFixture.make(in: directory, names: ["a.txt", "b.txt", "c.txt"])
            defer { fixture.workspace.close() }
            fixture.recordBack([fixture.place("a.txt", line: 5), fixture.place("b.txt", line: 10), fixture.place("c.txt", line: 30)])
            let model = RecentLocationsViewModel(tracker: fixture.tracker, workspace: fixture.workspace, loadTexts: instantLoader)

            model.moveSelection(-1)
            #expect(model.selectedIndex == 2)
            model.moveSelection(1)
            #expect(model.selectedIndex == 0)
            model.moveSelection(1)
            #expect(model.selectedIndex == 1)
            model.select(99)
            #expect(model.selectedIndex == 1)
            model.select(2)
            #expect(model.selectedRow?.fileName == "a.txt")
        }
    }

    @Test
    func emptyModelsIgnoreSelectionActivationAndRemoval() async throws {
        try withTempDir { directory in
            let fixture = try RecentLocationsPopupFixture.make(in: directory, names: ["a.txt"])
            defer { fixture.workspace.close() }
            let model = RecentLocationsViewModel(tracker: fixture.tracker, workspace: fixture.workspace, loadTexts: instantLoader)
            let dismissals = RecentLocationsDismissals()
            model.dismiss = { dismissals.restoreFlags.append($0) }

            model.moveSelection(1)
            model.activate()
            model.removeSelected()

            #expect(model.rows.isEmpty)
            #expect(model.selectedRow == nil)
            #expect(model.countText == "(0)")
            #expect(dismissals.restoreFlags.isEmpty)
        }
    }

    @Test
    func activatingARowDismissesWithoutRestoringFocusAndNavigates() async throws {
        try withTempDir { directory in
            let fixture = try RecentLocationsPopupFixture.make(in: directory, names: ["a.txt", "b.txt"])
            defer { fixture.workspace.close() }
            try fixture.open("a.txt", line: 1)
            try fixture.open("b.txt", line: 15)
            fixture.recordBack([fixture.place("a.txt", line: 7, column: 3)])
            let model = RecentLocationsViewModel(tracker: fixture.tracker, workspace: fixture.workspace, loadTexts: instantLoader)
            let dismissals = RecentLocationsDismissals()
            model.dismiss = { dismissals.restoreFlags.append($0) }

            model.open(0)

            #expect(dismissals.restoreFlags == [false])
            #expect(fixture.selectedName == "a.txt")
            #expect(fixture.caretLine == 7)
            #expect(fixture.tracker.history.backPlaces.map(\.fileURL.lastPathComponent).contains("b.txt"))
        }
    }

    @Test
    func activatingWithoutADismissHandlerStillNavigates() async throws {
        try withTempDir { directory in
            let fixture = try RecentLocationsPopupFixture.make(in: directory, names: ["a.txt", "b.txt"])
            defer { fixture.workspace.close() }
            try fixture.open("a.txt", line: 1)
            try fixture.open("b.txt", line: 15)
            fixture.recordBack([fixture.place("a.txt", line: 9)])
            let model = RecentLocationsViewModel(tracker: fixture.tracker, workspace: fixture.workspace, loadTexts: instantLoader)

            model.activate()

            #expect(fixture.selectedName == "a.txt")
            #expect(fixture.caretLine == 9)
        }
    }

    @Test
    func removingTheSelectedRowKeepsTheSelectionInRange() async throws {
        try withTempDir { directory in
            let fixture = try RecentLocationsPopupFixture.make(in: directory, names: ["a.txt", "b.txt", "c.txt"])
            defer { fixture.workspace.close() }
            fixture.recordBack([fixture.place("a.txt", line: 5), fixture.place("b.txt", line: 10), fixture.place("c.txt", line: 30)])
            let model = RecentLocationsViewModel(tracker: fixture.tracker, workspace: fixture.workspace, loadTexts: instantLoader)
            model.select(1)

            model.removeSelected()
            #expect(names(model) == ["c.txt", "a.txt"])
            #expect(model.selectedIndex == 1)

            model.removeSelected()
            #expect(names(model) == ["c.txt"])
            #expect(model.selectedIndex == 0)

            model.removeSelected()
            #expect(model.rows.isEmpty)
            #expect(model.selectedIndex == 0)
            #expect(fixture.tracker.history.backPlaces.isEmpty)
        }
    }

    @Test
    func removingInChangedModeLeavesNavigationPlacesAlone() async throws {
        try withTempDir { directory in
            let fixture = try RecentLocationsPopupFixture.make(in: directory, names: ["a.txt", "c.txt"])
            defer { fixture.workspace.close() }
            fixture.recordBack([fixture.place("a.txt", line: 5)])
            fixture.recordChanges([fixture.place("c.txt", line: 7)])
            let model = RecentLocationsViewModel(
                tracker: fixture.tracker,
                workspace: fixture.workspace,
                showChangedOnly: true,
                loadTexts: instantLoader
            )

            model.removeSelected()

            #expect(model.rows.isEmpty)
            #expect(fixture.tracker.history.changePlaces.isEmpty)
            #expect(fixture.tracker.history.backPlaces.count == 1)
        }
    }

    @Test
    func keysDriveTheList() async throws {
        try withTempDir { directory in
            let fixture = try RecentLocationsPopupFixture.make(in: directory, names: ["a.txt", "b.txt", "c.txt"])
            defer { fixture.workspace.close() }
            try fixture.open("c.txt", line: 1)
            fixture.recordBack([fixture.place("a.txt", line: 5), fixture.place("b.txt", line: 10)])
            let model = RecentLocationsViewModel(tracker: fixture.tracker, workspace: fixture.workspace, loadTexts: instantLoader)
            let dismissals = RecentLocationsDismissals()
            model.dismiss = { dismissals.restoreFlags.append($0) }

            #expect(model.handle(event: try recentLocationsKeyEvent(125)))
            #expect(model.selectedIndex == 1)
            #expect(model.handle(event: try recentLocationsKeyEvent(126)))
            #expect(model.selectedIndex == 0)
            #expect(model.handle(event: try recentLocationsKeyEvent(51)))
            #expect(names(model) == ["a.txt"])
            #expect(model.handle(event: try recentLocationsKeyEvent(53)))
            #expect(dismissals.restoreFlags == [true])
            #expect(!model.handle(event: try recentLocationsKeyEvent(0)))
            #expect(!model.handle(event: try recentLocationsKeyEvent(53, modifiers: .command)))
            #expect(model.handle(event: try recentLocationsKeyEvent(36)))
            #expect(dismissals.restoreFlags == [true, false])
            #expect(fixture.selectedName == "a.txt")
        }
    }

    @Test
    func enterOnTheKeypadAndForwardDeleteWork() async throws {
        try withTempDir { directory in
            let fixture = try RecentLocationsPopupFixture.make(in: directory, names: ["a.txt", "b.txt"])
            defer { fixture.workspace.close() }
            try fixture.open("b.txt", line: 1)
            fixture.recordBack([fixture.place("a.txt", line: 5), fixture.place("b.txt", line: 10)])
            let model = RecentLocationsViewModel(tracker: fixture.tracker, workspace: fixture.workspace, loadTexts: instantLoader)

            #expect(model.handle(event: try recentLocationsKeyEvent(117)))
            #expect(names(model) == ["a.txt"])
            #expect(model.handle(event: try recentLocationsKeyEvent(76)))
            #expect(fixture.selectedName == "a.txt")
        }
    }

    @Test
    func closingTheModelCancelsPendingLoads() async throws {
        try await withTempDir { directory in
            let fixture = try RecentLocationsPopupFixture.make(in: directory, names: ["a.txt"])
            defer { fixture.workspace.close() }
            fixture.recordBack([fixture.place("a.txt", line: 2)])
            let calls = RecentLocationsLoaderCalls()
            var model: RecentLocationsViewModel? = RecentLocationsViewModel(
                tracker: fixture.tracker,
                workspace: fixture.workspace,
                loadTexts: { urls in
                    calls.record(urls)
                    try? await Task.sleep(for: .seconds(30))
                    return Dictionary(uniqueKeysWithValues: urls.map { ($0, "late") })
                }
            )
            try await eventually { !calls.batches.isEmpty }
            let rows = model?.rows

            model = nil
            try await Task.sleep(for: .milliseconds(50))

            #expect(rows?.map(\.preview) == [RecentLocationsPreview.pending])
            #expect(model == nil)
        }
    }

    @Test
    func textSourcesProvideNothingWithoutAWorkspaceAndSkipUnreadableFiles() async throws {
        try await withTempDir { directory in
            let readable = directory.appending(path: "ok.txt")
            try "content".write(to: readable, atomically: true, encoding: .utf8)
            let missing = directory.appending(path: "missing.txt")

            #expect(RecentLocationsTextSource.openTexts(for: [readable], workspace: nil).isEmpty)
            let loaded = await RecentLocationsTextLoader.read([readable, missing])
            #expect(loaded == [readable: "content"])
        }
    }
}
