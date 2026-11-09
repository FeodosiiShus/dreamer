import AppKit
import OrderedCollections
import SwiftUI
import Testing
@testable import Dreamder

struct TabDragStub: DragLocated {
    let startLocation: CGPoint
    let location: CGPoint
}

@MainActor
@Suite(.uiGate)
struct EditorTabStripModelCoverageTests {
    private func strip(measuring locations: Bool = true) -> EditorTabStripModel {
        let model = EditorTabStripModel()
        model.openedTabs = ["a", "b", "c"]
        for id in model.openedTabs {
            model.tabWidth[id] = 100
        }
        if locations {
            model.tabLocations["a"] = CGRect(x: 0, y: 0, width: 100, height: 30)
            model.tabLocations["b"] = CGRect(x: 104, y: 0, width: 100, height: 30)
            model.tabLocations["c"] = CGRect(x: 208, y: 0, width: 100, height: 30)
        }
        return model
    }

    private func makeEditor(_ names: [String]) -> Editor {
        Editor(files: OrderedSet(names.map { CEWorkspaceFile(url: URL(filePath: "/fake/dir/\($0)")) }))
    }

    @Test
    func dragIsIgnoredWhileTheCloseButtonGestureIsActive() {
        let model = strip()
        model.closeButtonGestureActive = true

        model.dragChanged(id: "b", startX: 150, currentX: 120)

        #expect(model.draggingTabId == nil)
        #expect(model.draggingStartLocation == nil)
        #expect(model.tabOffsets.isEmpty)
    }

    @Test
    func firstChangeStartsTheDragWithoutMovingTheTab() {
        let model = strip()

        model.dragChanged(id: "b", startX: 150, currentX: 150)

        #expect(model.draggingTabId == "b")
        #expect(model.draggingStartLocation == 150)
        #expect(model.draggingLastLocation == 150)
        #expect(model.tabOffsets["b"] == 0)
        #expect(model.openedTabs == ["a", "b", "c"])
    }

    @Test
    func theDragHandlerForwardsGestureValuesToTheStrip() {
        let model = strip()
        let handler = EditorTabDragHandler(id: "b", strip: model, editor: makeEditor(["x"]))

        handler.changed(TabDragStub(startLocation: CGPoint(x: 150, y: 0), location: CGPoint(x: 150, y: 0)))
        #expect(model.draggingTabId == "b")
        #expect(model.draggingStartLocation == 150)

        handler.ended(TabDragStub(startLocation: CGPoint(x: 150, y: 0), location: CGPoint(x: 160, y: 0)))
        #expect(model.draggingStartLocation == nil)
        #expect(model.draggingLastLocation == nil)
    }

    @Test
    func dragOfAnUnmeasuredOrUnknownTabOnlyRecordsTheStart() {
        let model = EditorTabStripModel()
        model.openedTabs = ["a"]

        model.dragChanged(id: "a", startX: 10, currentX: 12)
        #expect(model.draggingTabId == "a")
        #expect(model.tabOffsets.isEmpty)

        model.tabWidth["ghost"] = 50
        model.dragChanged(id: "ghost", startX: 10, currentX: 12)
        #expect(model.draggingTabId == "ghost")
        #expect(model.tabOffsets.isEmpty)
    }

    @Test
    func draggingLeftPastThePreviousTabSwapsThem() {
        let model = strip()
        model.dragChanged(id: "b", startX: 150, currentX: 150)

        model.dragChanged(id: "b", startX: 150, currentX: 80)

        #expect(model.openedTabs == ["b", "a", "c"])
        #expect(model.draggingStartLocation == 46)
        #expect(model.tabOffsets["b"] == 34)
    }

    @Test
    func draggingRightPastTheNextTabSwapsThem() {
        let model = strip()
        model.dragChanged(id: "b", startX: 150, currentX: 150)

        model.dragChanged(id: "b", startX: 150, currentX: 230)

        #expect(model.openedTabs == ["a", "c", "b"])
        #expect(model.draggingStartLocation == 254)
        #expect(model.tabOffsets["b"] == -24)
    }

    @Test
    func draggingInsideTheNeighbourThresholdKeepsOrderAndThrottlesTheLastLocation() {
        let model = strip()
        model.dragChanged(id: "b", startX: 150, currentX: 150)

        model.dragChanged(id: "b", startX: 150, currentX: 95)
        #expect(model.openedTabs == ["a", "b", "c"])
        #expect(model.draggingLastLocation == 95)
        #expect(model.tabOffsets["b"] == -55)

        model.dragChanged(id: "b", startX: 150, currentX: 92)
        #expect(model.draggingLastLocation == 95)

        model.dragChanged(id: "b", startX: 150, currentX: 200)
        #expect(model.openedTabs == ["a", "b", "c"])
        #expect(model.draggingLastLocation == 200)
    }

    @Test
    func draggingTheFirstTabLeftOrTheLastTabRightNeverSwaps() {
        let model = strip()
        model.dragChanged(id: "a", startX: 50, currentX: 50)
        model.dragChanged(id: "a", startX: 50, currentX: 20)
        #expect(model.openedTabs == ["a", "b", "c"])
        #expect(model.draggingLastLocation == 20)

        model.dragChanged(id: "c", startX: 250, currentX: 250)
        model.dragChanged(id: "c", startX: 250, currentX: 400)
        #expect(model.openedTabs == ["a", "b", "c"])
        #expect(model.draggingLastLocation == 400)
    }

    @Test
    func unmeasuredNeighboursStopTheDragStep() {
        let model = strip(measuring: false)
        model.dragChanged(id: "b", startX: 150, currentX: 150)

        model.dragChanged(id: "b", startX: 150, currentX: 80)
        #expect(model.openedTabs == ["a", "b", "c"])
        #expect(model.draggingLastLocation == 150)
        #expect(model.tabOffsets["b"] == -70)

        model.dragChanged(id: "b", startX: 150, currentX: 230)
        #expect(model.openedTabs == ["a", "b", "c"])
        #expect(model.draggingLastLocation == 150)
        #expect(model.tabOffsets["b"] == 80)
    }

    @Test
    func releasingTheDragCommitsTheNewOrderToTheEditor() async throws {
        let model = strip()
        let editor = makeEditor(["a", "b", "c"])
        model.openedTabs = editor.tabs.map(\.file.id).reversed()
        model.draggingTabId = model.openedTabs[1]
        model.draggingStartLocation = 5
        model.draggingLastLocation = 7
        model.tabOffsets[model.openedTabs[0]] = 30

        model.dragEnded(editor: editor)

        #expect(model.draggingStartLocation == nil)
        #expect(model.draggingLastLocation == nil)
        #expect(model.tabOffsets.isEmpty)
        let expected = model.openedTabs
        try await eventually(timeout: .seconds(2)) {
            editor.tabs.map(\.file.id) == expected && model.draggingTabId == nil
        }
    }

    @Test
    func aNewDragBeforeTheCommitKeepsTheEditorOrder() async throws {
        let model = strip()
        let editor = makeEditor(["a", "b", "c"])
        let original = editor.tabs.map(\.file.id)
        model.openedTabs = original.reversed()

        model.dragEnded(editor: editor)
        model.draggingStartLocation = 3

        try await Task.sleep(for: .milliseconds(600))
        #expect(editor.tabs.map(\.file.id) == original)
        #expect(model.draggingTabId == nil)
    }

    @Test
    func synchronizingMirrorsTheEditorTabs() {
        let model = EditorTabStripModel()
        let editor = makeEditor(["x", "y"])

        model.synchronizeTabs(with: editor)

        #expect(model.openedTabs == editor.tabs.map(\.file.id))
    }

    @Test
    func hiddenTabsAreTheOnesOutsideTheViewport() {
        let model = strip()

        let hidden = model.hiddenTabs(in: CGRect(x: 0, y: 0, width: 210, height: 30))

        #expect(hidden == ["c"])
        #expect(model.hiddenTabs(in: .zero).isEmpty)
    }

    @Test
    func activatingATabSelectsItInTheEditorAndMakesTheEditorActive() throws {
        try withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: ["a.swift", "b.swift"])
            defer { harness.close() }
            let model = EditorTabStripModel()
            let first = try harness.file("a.swift")
            #expect(harness.editor.selectedTab?.file == harness.files[1])
            let other = try #require(harness.manager.splitActiveEditor(.trailing, workspace: harness.workspace))
            #expect(harness.manager.activeEditor === other)

            let activated = model.activate(first.id, in: harness.editor, editorManager: harness.manager)

            #expect(activated)
            #expect(harness.editor.selectedTab?.file == first)
            #expect(harness.manager.activeEditor === harness.editor)
            #expect(harness.editor.history.first == first)
        }
    }

    @Test
    func activatingAnUnknownTabChangesNothing() throws {
        try withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: ["a.swift"])
            defer { harness.close() }
            let model = EditorTabStripModel()
            let selected = harness.editor.selectedTab

            let activated = model.activate("missing", in: harness.editor, editorManager: harness.manager)

            #expect(activated == false)
            #expect(harness.editor.selectedTab == selected)
        }
    }

    @Test
    func tabIDsAreStableAcrossKinds() throws {
        let identifier = UUID()
        let code = EditorTabID.codeEditor("/tmp/a.swift")
        let extensionTab = EditorTabID.extensionInstallation(identifier)

        #expect(code.id == "codeEditor_/tmp/a.swift")
        #expect(extensionTab.id == "extensionInstallation_\(identifier.uuidString)")
        let decoded = try JSONDecoder().decode(EditorTabID.self, from: JSONEncoder().encode(code))
        #expect(decoded == code)
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct EditorTabsHostedCoverageTests {
    private func menuTitles(_ menu: NSMenu) -> [String] {
        menu.update()
        return menu.items.map(\.title)
    }

    @Test
    func stripRendersEveryTabAndFollowsTheSelection() async throws {
        try await withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(
                in: directory,
                names: ["One.swift", "Two.swift", "Three.test.ts"]
            )
            defer { harness.close() }
            let hosted = try harness.host(size: NSSize(width: 900, height: 80)) {
                EditorTabs()
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(500))
            #expect(hosted.renders())
            let before = hosted.snapshot()

            harness.editor.setSelectedTab(harness.files[0])
            try await hosted.settle(.milliseconds(500))

            #expect(harness.editor.selectedTab?.file == harness.files[0])
            #expect(HostedView.pixelsDiffer(before, hosted.snapshot()))
        }
    }

    @Test
    func addingReorderingAndClosingTabsResynchronisesTheStrip() async throws {
        try await withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: ["One.swift", "Two.swift"])
            defer { harness.close() }
            let hosted = try harness.host(size: NSSize(width: 900, height: 80)) {
                EditorTabs()
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(400))
            let initial = hosted.snapshot()

            try "let extra = 2\n".write(
                to: directory.appending(path: "Extra.swift"),
                atomically: true,
                encoding: .utf8
            )
            let extra = try #require(harness.workspace.workspaceFileManager?.getFile(
                directory.appending(path: "Extra.swift").path(percentEncoded: false),
                createIfNotFound: true
            ))
            harness.manager.openTab(item: extra)
            try await hosted.settle(.milliseconds(400))
            #expect(harness.editor.tabs.count == 3)
            let grown = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(initial, grown))

            harness.editor.tabs = OrderedSet(harness.editor.tabs.reversed())
            try await hosted.settle(.milliseconds(400))
            #expect(harness.editor.tabs.map(\.file.name) == ["Extra.swift", "Two.swift", "One.swift"])
            #expect(HostedView.pixelsDiffer(grown, hosted.snapshot()))

            harness.editor.closeTab(file: extra)
            try await hosted.settle(.milliseconds(400))
            #expect(harness.editor.tabs.count == 2)
            #expect(hosted.renders())
        }
    }

    @Test
    func resizingATabByEditingItRelayoutsTheStrip() async throws {
        try await withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: ["One.swift", "Two.swift"])
            defer { harness.close() }
            let first = harness.files[0]
            harness.editor.setSelectedTab(first)
            let hosted = try harness.host(size: NSSize(width: 900, height: 80)) {
                EditorTabs()
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(400))
            let document = try #require(first.fileDocument)
            document.updateChangeCount(.changeDone)
            first.fileDocument = document
            try await hosted.settle(.milliseconds(400))
            #expect(document.isDocumentEdited)
            let edited = hosted.snapshot()

            harness.editor.setSelectedTab(harness.files[1])
            try await hosted.settle(.milliseconds(500))

            #expect(HostedView.pixelsDiffer(edited, hosted.snapshot()))
            document.updateChangeCount(.changeCleared)
        }
    }

    @Test
    func revealingAHiddenTabSelectsItActivatesItsEditorAndScrollsToIt() async throws {
        try await withTempDir { directory in
            let names = (1...6).map { "ALongerTabFileName\($0).swift" }
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: names)
            defer { harness.close() }
            let model = EditorTabStripModel()
            let hosted = try harness.host(size: NSSize(width: 360, height: 80)) {
                EditorTabs(strip: model)
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(600))
            let other = try #require(harness.manager.splitActiveEditor(.trailing, workspace: harness.workspace))
            #expect(harness.manager.activeEditor === other)
            let target = try #require(harness.files.first)

            model.reveal(target.id, in: harness.editor, editorManager: harness.manager)

            #expect(harness.editor.selectedTab?.file == target)
            #expect(harness.manager.activeEditor === harness.editor)
            try await eventually(timeout: .seconds(30)) { model.revealedTabID == nil }
        }
    }

    @Test
    func pinningATabResynchronisesThePinnedTabsOfTheStrip() async throws {
        try await withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: ["One.swift", "Two.swift"])
            defer { harness.close() }
            let model = EditorTabStripModel()
            let hosted = try harness.host(size: NSSize(width: 900, height: 80)) {
                EditorTabs(strip: model)
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(400))
            let second = try #require(harness.files.last)
            #expect(model.pinnedTabs.isEmpty)

            harness.editor.setPinned(true, file: second)

            try await eventually(timeout: .seconds(30)) { model.pinnedTabs == [second.id] }
            #expect(model.openedTabs.first == second.id)
        }
    }

    @Test
    func tabsOutsideTheViewportAddTheHiddenTabsButton() async throws {
        try await withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(
                in: directory,
                names: ["One.swift", "Two.swift", "Three.swift"]
            )
            defer { harness.close() }
            let model = EditorTabStripModel()
            let hosted = try harness.host(size: NSSize(width: 600, height: 80)) {
                EditorTabs(strip: model)
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(400))
            let before = hosted.snapshot()
            #expect(model.hiddenTabs(in: model.viewportFrame).isEmpty)

            model.viewportFrame = CGRect(x: 0, y: 0, width: 100, height: 40)
            for id in model.openedTabs {
                model.tabLocations[id] = CGRect(x: 4000, y: 0, width: 80, height: 30)
            }
            try await hosted.settle(.milliseconds(400))

            #expect(!model.hiddenTabs(in: model.viewportFrame).isEmpty)
            #expect(HostedView.pixelsDiffer(before, hosted.snapshot()))
        }
    }

    @Test
    func hiddenTabsMenuListsTheHiddenFilesAndRevealsTheChosenOne() throws {
        let editor = Editor(files: OrderedSet([
            CEWorkspaceFile(url: URL(filePath: "/fake/dir/One.swift")),
            CEWorkspaceFile(url: URL(filePath: "/fake/dir/Two.swift")),
            CEWorkspaceFile(url: URL(filePath: "/fake/dir/Three.ts"))
        ]))
        let hidden = editor.tabs.dropFirst().map(\.file.id)
        let strip = EditorTabStripModel()
        let manager = EditorManager()
        let menu = NSHostingMenu(
            rootView: EditorHiddenTabsMenuContent(hidden: hidden, strip: strip, editor: editor, editorManager: manager)
        )

        #expect(menuTitles(menu) == ["Two.swift", "Three.ts"])
        menu.performActionForItem(at: 1)

        #expect(strip.revealedTabID == hidden.last)
        #expect(editor.selectedTab?.file.id == hidden.last)
        #expect(manager.activeEditor === editor)
    }

    @Test
    func hiddenTabsMenuIgnoresTabsThatAreGone() {
        let strip = EditorTabStripModel()
        let menu = NSHostingMenu(
            rootView: EditorHiddenTabsMenuContent(
                hidden: ["missing"],
                strip: strip,
                editor: Editor(),
                editorManager: EditorManager()
            )
        )
        menu.update()

        for index in menu.items.indices {
            menu.performActionForItem(at: index)
        }

        #expect(strip.revealedTabID == nil)
    }
}
