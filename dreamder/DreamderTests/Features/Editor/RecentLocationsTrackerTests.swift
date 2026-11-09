import CodeEditSourceEditor
import Foundation
import Testing
@testable import Dreamder

@MainActor
private final class RecentLocationsTrackerHolder {
    var tracker: RecentLocationsTracker?
    var navigatingDuringReplay: Bool?
    var openedPlaces: [EditorPlace] = []
}

@MainActor
@Suite(.uiGate)
struct RecentLocationsTrackerTests {
    private func makeWorkspace(in directory: URL, names: [String]) throws -> WorkspaceDocument {
        for name in names {
            let text = (1...60).map { "line \($0) of \(name)" }.joined(separator: "\n")
            try text.write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
        }
        return try HostedViewFixture.makeWorkspace(in: directory)
    }

    private func open(_ name: String, in workspace: WorkspaceDocument, directory: URL, line: Int? = nil) throws {
        let file = try #require(workspace.workspaceFileManager?.getFile(
            directory.appending(path: name).path(percentEncoded: false),
            createIfNotFound: true
        ))
        workspace.editorManager?.openTab(item: file)
        if let line {
            workspace.editorManager?.activeEditor.selectedTab?.cursorPositions = [CursorPosition(line: line, column: 1)]
        }
    }

    private func selectedName(_ workspace: WorkspaceDocument) -> String? {
        workspace.editorManager?.activeEditor.selectedTab?.file.url.lastPathComponent
    }

    private func caretLine(_ workspace: WorkspaceDocument) -> Int? {
        workspace.editorManager?.activeEditor.selectedTab?.cursorPositions.first?.start.line
    }

    private func isCurrent(_ tracker: RecentLocationsTracker, _ name: String, line: Int) -> Bool {
        tracker.currentPlace?.fileURL.lastPathComponent == name && tracker.currentPlace?.line == line
    }

    private func names(_ places: [EditorPlace]) -> [String] {
        places.map { $0.fileURL.lastPathComponent }
    }

    @Test
    func fileSwitchesAreRecordedAsBackPlaces() async throws {
        try await withTempDir { directory in
            let workspace = try makeWorkspace(in: directory, names: ["a.txt", "b.txt"])
            defer { workspace.close() }
            let tracker = RecentLocationsStore.shared.history(for: workspace)

            try open("a.txt", in: workspace, directory: directory, line: 12)
            try await eventually { isCurrent(tracker, "a.txt", line: 12) }
            #expect(!tracker.isBackAvailable)

            try open("b.txt", in: workspace, directory: directory)
            try await eventually { names(tracker.history.backPlaces) == ["a.txt"] }

            #expect(tracker.history.backPlaces.first?.line == 12)
            #expect(tracker.isBackAvailable)
            #expect(!tracker.isForwardAvailable)
            #expect(tracker.currentPlace?.fileURL.lastPathComponent == "b.txt")
        }
    }

    @Test
    func caretMovesInsideAFileAreNotRecorded() async throws {
        try await withTempDir { directory in
            let workspace = try makeWorkspace(in: directory, names: ["a.txt"])
            defer { workspace.close() }
            let tracker = RecentLocationsStore.shared.history(for: workspace)
            try open("a.txt", in: workspace, directory: directory, line: 3)
            try await eventually { isCurrent(tracker, "a.txt", line: 3) }

            workspace.editorManager?.activeEditor.selectedTab?.cursorPositions = [CursorPosition(line: 45, column: 2)]
            try await eventually { isCurrent(tracker, "a.txt", line: 45) }

            #expect(tracker.history.backPlaces.isEmpty)
            #expect(tracker.currentPlace?.column == 2)
        }
    }

    @Test
    func closingTheLastTabRecordsTheLeftPlace() async throws {
        try await withTempDir { directory in
            let workspace = try makeWorkspace(in: directory, names: ["a.txt"])
            defer { workspace.close() }
            let tracker = RecentLocationsStore.shared.history(for: workspace)
            try open("a.txt", in: workspace, directory: directory, line: 9)
            try await eventually { isCurrent(tracker, "a.txt", line: 9) }

            workspace.editorManager?.activeEditor.closeSelectedTab()

            try await eventually { tracker.currentPlace == nil }
            #expect(names(tracker.history.backPlaces) == ["a.txt"])
        }
    }

    @Test
    func goBackAndForwardSwitchTabsAndCarets() async throws {
        try await withTempDir { directory in
            let workspace = try makeWorkspace(in: directory, names: ["a.txt", "b.txt"])
            defer { workspace.close() }
            let tracker = RecentLocationsStore.shared.history(for: workspace)
            try open("a.txt", in: workspace, directory: directory, line: 12)
            try await eventually { isCurrent(tracker, "a.txt", line: 12) }
            try open("b.txt", in: workspace, directory: directory, line: 20)
            try await eventually { isCurrent(tracker, "b.txt", line: 20) }
            #expect(names(tracker.history.backPlaces) == ["a.txt"])
            #expect(EditorLocationHistoryCommands.canGoBack(workspace: workspace))
            #expect(!EditorLocationHistoryCommands.canGoForward(workspace: workspace))

            EditorLocationHistoryCommands.goBack(workspace: workspace)

            #expect(selectedName(workspace) == "a.txt")
            #expect(caretLine(workspace) == 12)
            #expect(!tracker.isNavigatingNow)
            try await Task.sleep(for: .milliseconds(250))
            #expect(tracker.history.backPlaces.isEmpty)
            #expect(names(tracker.history.forwardPlaces) == ["b.txt"])
            #expect(!EditorLocationHistoryCommands.canGoBack(workspace: workspace))
            #expect(EditorLocationHistoryCommands.canGoForward(workspace: workspace))

            EditorLocationHistoryCommands.goForward(workspace: workspace)

            #expect(selectedName(workspace) == "b.txt")
            #expect(caretLine(workspace) == 20)
            try await Task.sleep(for: .milliseconds(250))
            #expect(names(tracker.history.backPlaces) == ["a.txt"])
            #expect(tracker.history.backPlaces.first?.line == 12)
            #expect(tracker.history.forwardPlaces.isEmpty)
        }
    }

    @Test
    func explicitNavigationRecordsThePlaceYouLeft() async throws {
        try await withTempDir { directory in
            let workspace = try makeWorkspace(in: directory, names: ["a.txt"])
            defer { workspace.close() }
            let tracker = RecentLocationsStore.shared.history(for: workspace)
            EditorLocationHistoryRecorder.includeCurrentCommandAsNavigation(workspace: workspace)
            #expect(tracker.history.backPlaces.isEmpty)
            try open("a.txt", in: workspace, directory: directory, line: 12)
            try await eventually { isCurrent(tracker, "a.txt", line: 12) }

            EditorLocationHistoryRecorder.includeCurrentCommandAsNavigation(workspace: workspace)
            #expect(tracker.history.backPlaces.map(\.line) == [12])
            LSPDefinitionNavigator.open(
                url: directory.appending(path: "a.txt"),
                position: CursorPosition(line: 40, column: 5),
                in: workspace
            )
            try await eventually { isCurrent(tracker, "a.txt", line: 40) }

            #expect(tracker.history.backPlaces.map(\.line) == [12])
            EditorLocationHistoryCommands.goBack(workspace: workspace)
            #expect(caretLine(workspace) == 12)
            #expect(tracker.history.forwardPlaces.map(\.line) == [40])
        }
    }

    @Test
    func commandsWithoutAWorkspaceDoNothing() {
        EditorLocationHistoryRecorder.includeCurrentCommandAsNavigation(workspace: nil)
        EditorLocationHistoryCommands.goBack(workspace: nil)
        EditorLocationHistoryCommands.goForward(workspace: nil)

        #expect(!EditorLocationHistoryCommands.canGoBack(workspace: nil))
        #expect(!EditorLocationHistoryCommands.canGoForward(workspace: nil))
    }

    @Test
    func replayIsFlaggedAndNeverRecorded() async throws {
        try withTempDir { directory in
            let workspace = try makeWorkspace(in: directory, names: ["a.txt"])
            defer { workspace.close() }
            try open("a.txt", in: workspace, directory: directory, line: 6)
            let seeded = EditorPlace(fileURL: URL(filePath: "/project/x.swift"), line: 5, column: 1)
            var history = EditorLocationHistory(isFileValid: { _ in true })
            history.recordBackPlace(seeded)
            let holder = RecentLocationsTrackerHolder()
            let tracker = RecentLocationsTracker(workspace: workspace, history: history) { _, place in
                holder.navigatingDuringReplay = holder.tracker?.isNavigatingNow
                holder.openedPlaces.append(place)
                holder.tracker?.includeCurrentCommandAsNavigation()
                holder.tracker?.recordNavigation(from: place)
                holder.tracker?.recordChange(place)
            }
            holder.tracker = tracker

            tracker.goBack()

            #expect(holder.navigatingDuringReplay == true)
            #expect(holder.openedPlaces == [seeded])
            #expect(!tracker.isNavigatingNow)
            #expect(tracker.history.backPlaces.isEmpty)
            #expect(tracker.history.changePlaces.isEmpty)
            #expect(names(tracker.history.forwardPlaces) == ["a.txt"])

            tracker.recordNavigation(from: seeded)
            tracker.recordChange(seeded)
            #expect(tracker.history.backPlaces == [seeded])
            #expect(tracker.history.changePlaces == [seeded])
            #expect(tracker.history.forwardPlaces.isEmpty)
        }
    }

    @Test
    func forwardUsesTheInjectedOpener() async throws {
        try withTempDir { directory in
            let workspace = try makeWorkspace(in: directory, names: ["a.txt"])
            defer { workspace.close() }
            try open("a.txt", in: workspace, directory: directory, line: 6)
            let seeded = EditorPlace(fileURL: URL(filePath: "/project/x.swift"), line: 5, column: 1)
            var history = EditorLocationHistory(isFileValid: { _ in true })
            history.recordBackPlace(seeded)
            _ = history.back(from: EditorPlace(fileURL: URL(filePath: "/project/y.swift"), line: 50, column: 4))
            let holder = RecentLocationsTrackerHolder()
            let tracker = RecentLocationsTracker(workspace: workspace, history: history) { _, place in
                holder.openedPlaces.append(place)
            }

            tracker.goForward()

            #expect(holder.openedPlaces.map(\.line) == [50])
            #expect(holder.openedPlaces.first?.column == 4)
            tracker.goForward()
            #expect(holder.openedPlaces.count == 1)
        }
    }

    @Test
    func navigatingToAPlaceRecordsTheCurrentPlaceFirst() async throws {
        try await withTempDir { directory in
            let workspace = try makeWorkspace(in: directory, names: ["a.txt", "b.txt"])
            defer { workspace.close() }
            let tracker = RecentLocationsStore.shared.history(for: workspace)
            try open("a.txt", in: workspace, directory: directory, line: 12)
            try await eventually { isCurrent(tracker, "a.txt", line: 12) }

            tracker.navigate(to: EditorPlace(fileURL: directory.appending(path: "b.txt"), line: 7, column: 2))

            #expect(selectedName(workspace) == "b.txt")
            #expect(caretLine(workspace) == 7)
            #expect(names(tracker.history.backPlaces) == ["a.txt"])
            try await Task.sleep(for: .milliseconds(250))
            #expect(names(tracker.history.backPlaces) == ["a.txt"])
            #expect(tracker.currentPlace?.line == 7)
        }
    }

    @Test
    func missingFilesAreSkippedByBackNavigation() async throws {
        try await withTempDir { directory in
            let workspace = try makeWorkspace(in: directory, names: ["a.txt", "b.txt", "c.txt"])
            defer { workspace.close() }
            let tracker = RecentLocationsStore.shared.history(for: workspace)
            try open("a.txt", in: workspace, directory: directory)
            try await eventually { isCurrent(tracker, "a.txt", line: 1) }
            try open("b.txt", in: workspace, directory: directory)
            try await eventually { names(tracker.history.backPlaces) == ["a.txt"] }
            try open("c.txt", in: workspace, directory: directory)
            try await eventually { names(tracker.history.backPlaces) == ["a.txt", "b.txt"] }
            try FileManager.default.removeItem(at: directory.appending(path: "a.txt"))

            tracker.goBack()

            #expect(selectedName(workspace) == "b.txt")
            #expect(!tracker.isBackAvailable)
            tracker.goBack()
            #expect(selectedName(workspace) == "b.txt")
            #expect(names(tracker.history.forwardPlaces) == ["c.txt"])
        }
    }

    @Test
    func removingPlacesDropsSimilarOnesFromTheChosenList() {
        let workspace = WorkspaceDocument()
        var history = EditorLocationHistory(isFileValid: { _ in true })
        let url = URL(filePath: "/project/a.swift")
        history.recordBackPlace(EditorPlace(fileURL: url, line: 10, column: 1))
        history.recordChangePlace(EditorPlace(fileURL: url, line: 10, column: 1))
        let tracker = RecentLocationsTracker(workspace: workspace, history: history)

        tracker.remove(EditorPlace(fileURL: url, line: 11, column: 1), changed: false)
        #expect(tracker.history.backPlaces.isEmpty)
        #expect(tracker.history.changePlaces.count == 1)

        tracker.remove(EditorPlace(fileURL: url, line: 12, column: 1), changed: true)
        #expect(tracker.history.changePlaces.isEmpty)
    }

    @Test
    func removeInvalidPlacesDropsPlacesOfMissingFiles() throws {
        try withTempDir { directory in
            let file = directory.appending(path: "doomed.swift")
            try "x".write(to: file, atomically: true, encoding: .utf8)
            var history = EditorLocationHistory()
            history.recordBackPlace(EditorPlace(fileURL: file, line: 1, column: 1))
            let workspace = WorkspaceDocument()
            let tracker = RecentLocationsTracker(workspace: workspace, history: history)
            #expect(tracker.isBackAvailable)

            try FileManager.default.removeItem(at: file)
            tracker.removeInvalidPlaces()

            #expect(!tracker.isBackAvailable)
            withExtendedLifetime(workspace) {}
        }
    }

    @Test
    func storeKeepsOneTrackerPerWorkspace() async throws {
        try withTempDir { directory in
            let firstDirectory = directory.appending(path: "first")
            let secondDirectory = directory.appending(path: "second")
            try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
            let first = try HostedViewFixture.makeWorkspace(in: firstDirectory)
            let second = try HostedViewFixture.makeWorkspace(in: secondDirectory)
            defer {
                first.close()
                second.close()
            }

            let tracker = RecentLocationsStore.shared.history(for: first)

            #expect(RecentLocationsStore.shared.history(for: first) === tracker)
            #expect(RecentLocationsStore.shared.history(for: second) !== tracker)
        }
    }
}
