import AppKit
import SwiftUI
import Testing
@testable import Dreamder

struct TabTestPointer: PointerLocated {
    let location: CGPoint
}

@MainActor
@Suite(.uiGate)
struct EditorTabCloseButtonCoverageTests {
    @Test
    func hitTestCoversTheSixteenPointSquareExclusively() {
        #expect(EditorTabClosePressModel.isInsideButton(CGPoint(x: 8, y: 8)))
        #expect(EditorTabClosePressModel.isInsideButton(CGPoint(x: 0.5, y: 15.5)))
        #expect(EditorTabClosePressModel.isInsideButton(CGPoint(x: 0, y: 8)) == false)
        #expect(EditorTabClosePressModel.isInsideButton(CGPoint(x: 16, y: 8)) == false)
        #expect(EditorTabClosePressModel.isInsideButton(CGPoint(x: 8, y: 0)) == false)
        #expect(EditorTabClosePressModel.isInsideButton(CGPoint(x: 8, y: 16)) == false)
        #expect(EditorTabClosePressModel.isInsideButton(CGPoint(x: -3, y: 8)) == false)
        #expect(EditorTabClosePressModel.isInsideButton(CGPoint(x: 8, y: 40)) == false)
    }

    @Test
    func pressRaisesTheGestureFlagAndOnlyAReleaseInsideTheButtonCloses() {
        let flags = EditorTabsCoverageFlags()
        let model = EditorTabClosePressModel()
        let active = Bindable(flags).gestureActive

        model.began(active: active)
        #expect(model.isPressing)
        #expect(flags.gestureActive)

        model.ended(at: CGPoint(x: 40, y: 8), active: active) { flags.closed += 1 }
        #expect(flags.closed == 0)
        #expect(model.isPressing == false)
        #expect(flags.gestureActive == false)

        model.began(active: active)
        model.ended(at: CGPoint(x: 8, y: 8), active: active) { flags.closed += 1 }
        #expect(flags.closed == 1)
        #expect(model.isPressing == false)
        #expect(flags.gestureActive == false)
    }

    @Test
    func hoveringTheCloseButtonHighlightsIt() async throws {
        let flags = EditorTabsCoverageFlags()
        let hosted = HostedViewFixture.host(size: NSSize(width: 60, height: 40)) {
            EditorTabCloseButton(
                closeAction: { flags.closed += 1 },
                closeButtonGestureActive: Bindable(flags).gestureActive,
                isHoveringClose: Bindable(flags).hovering
            )
        }
        defer { hosted.close() }
        try await hosted.settle()
        let resting = hosted.snapshot()
        #expect(hosted.renders())

        flags.hovering = true
        try await hosted.settle()

        #expect(HostedView.pixelsDiffer(resting, hosted.snapshot()))
    }

    @Test
    func theButtonRoutesPressesAndHoversThroughItsBindings() {
        let flags = EditorTabsCoverageFlags()
        let button = EditorTabCloseButton(
            closeAction: { flags.closed += 1 },
            closeButtonGestureActive: Bindable(flags).gestureActive,
            isHoveringClose: Bindable(flags).hovering
        )

        button.hoverChanged(true)
        #expect(flags.hovering)
        button.hoverChanged(false)
        #expect(flags.hovering == false)

        button.pressBegan(TabTestPointer(location: CGPoint(x: 8, y: 8)))
        #expect(flags.gestureActive)
        button.pressEnded(TabTestPointer(location: CGPoint(x: 90, y: 8)))
        #expect(flags.closed == 0)
        #expect(flags.gestureActive == false)

        button.pressBegan(TabTestPointer(location: CGPoint(x: 8, y: 8)))
        button.pressEnded(TabTestPointer(location: CGPoint(x: 8, y: 8)))
        #expect(flags.closed == 1)
        #expect(flags.gestureActive == false)
    }

    @Test
    func thePinButtonReportsHoverThroughItsBinding() {
        let flags = EditorTabsCoverageFlags()
        let button = EditorTabPinButton(unpinAction: { flags.closed += 1 }, isHoveringClose: Bindable(flags).hovering)

        button.hoverChanged(true)
        #expect(flags.hovering)
        button.hoverChanged(false)
        #expect(flags.hovering == false)
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct EditorTabViewCoverageTests {
    private func hostTab(
        _ harness: EditorTabsCoverageHarness,
        file: CEWorkspaceFile,
        interaction: EditorTabInteraction = EditorTabInteraction(),
        dragging: String? = nil,
        focused: Bool = true
    ) throws -> HostedView {
        try harness.host(size: NSSize(width: 320, height: 60), focused: focused) {
            EditorTabView(
                file: file,
                index: 0,
                draggingTabId: dragging,
                closeButtonGestureActive: .constant(false),
                interaction: interaction
            )
        }
    }

    @Test
    func hoverStateTracksTheCursorAndClearsTheCloseHover() async throws {
        let interaction = EditorTabInteraction()
        interaction.isHoveringClose = true

        interaction.hoverChanged(true)
        #expect(interaction.isHovering)
        #expect(interaction.isHoveringClose)

        interaction.hoverChanged(false)
        #expect(interaction.isHovering == false)
        #expect(interaction.isHoveringClose == false)
        try await Task.sleep(for: .milliseconds(100))
    }

    @Test
    func gestureMethodsActOnTheBoundContextAndIgnoreAnUnboundInteraction() throws {
        try withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: ["a.swift", "b.swift"])
            defer { harness.close() }
            let first = try harness.file("a.swift")
            let interaction = EditorTabInteraction()
            let pointer = TabTestPointer(location: CGPoint(x: 8, y: 8))

            interaction.unpinTab()
            interaction.closeTab()
            interaction.dragChanged(pointer)
            interaction.dragEnded(pointer)
            interaction.doubleTapEnded(())
            #expect(harness.editor.tabs.count == 2)
            #expect(harness.editor.selectedTab?.file.name == "b.swift")

            interaction.context = harness.context(first)
            interaction.dragChanged(pointer)
            #expect(interaction.isPressing)
            interaction.dragEnded(pointer)
            #expect(harness.editor.selectedTab?.file == first)

            harness.editor.temporaryTab = harness.editor.tabs.first { $0.file == first }
            interaction.doubleTapEnded(())
            #expect(harness.editor.temporaryTab == nil)

            harness.editor.setPinned(true, file: first)
            interaction.unpinTab()
            #expect(!harness.editor.isPinned(first))

            interaction.closeTab()
            #expect(harness.editor.tabs.map(\.file.name) == ["b.swift"])
        }
    }

    @Test
    func pressSelectsTheTabOnlyWhenItStartedOutsideTheCloseButton() async throws {
        try withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: ["a.swift", "b.swift"])
            defer { harness.close() }
            let first = try harness.file("a.swift")
            let context = harness.context(first)
            let interaction = EditorTabInteraction()
            #expect(harness.editor.selectedTab?.file.name == "b.swift")

            interaction.pressEnded(context)
            #expect(harness.editor.selectedTab?.file.name == "b.swift")

            interaction.isHoveringClose = true
            interaction.pressBegan()
            #expect(interaction.isPressing == false)

            interaction.isHoveringClose = false
            interaction.pressBegan()
            #expect(interaction.isPressing)
            interaction.pressEnded(context)
            #expect(interaction.isPressing == false)
            #expect(harness.editor.selectedTab?.file == first)
        }
    }

    @Test
    func selectActivatesTheEditorAndRecordsHistory() async throws {
        try withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: ["a.swift", "b.swift"])
            defer { harness.close() }
            let first = try harness.file("a.swift")
            let other = try #require(harness.manager.splitActiveEditor(.trailing, workspace: harness.workspace))
            #expect(harness.manager.activeEditor === other)

            EditorTabInteraction().select(harness.context(first))

            #expect(harness.manager.activeEditor === harness.editor)
            #expect(harness.editor.selectedTab?.file == first)
            #expect(harness.editor.history.first == first)

            let before = harness.editor.history.count
            EditorTabInteraction().select(harness.context(first))
            #expect(harness.editor.history.count == before)
        }
    }

    @Test
    func closeRemovesTheTabFromTheEditor() async throws {
        try withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: ["a.swift", "b.swift"])
            defer { harness.close() }
            let first = try harness.file("a.swift")

            EditorTabInteraction().close(harness.context(first))

            #expect(harness.editor.tabs.map(\.file.name) == ["b.swift"])
        }
    }

    @Test
    func doubleTapPromotesOnlyTheTemporaryTab() async throws {
        try withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: ["a.swift", "b.swift"])
            defer { harness.close() }
            let first = try harness.file("a.swift")
            let second = try harness.file("b.swift")
            let interaction = EditorTabInteraction()
            let secondTab = try #require(harness.editor.tabs.first { $0.file == second })
            harness.editor.temporaryTab = secondTab
            #expect(harness.context(first).isTemporary == false)
            #expect(harness.context(second).isTemporary)

            interaction.doubleTapped(harness.context(first))
            #expect(harness.editor.temporaryTab == secondTab)

            interaction.doubleTapped(harness.context(second))
            #expect(harness.editor.temporaryTab == nil)
        }
    }

    @Test
    func middleClickClosesTheHoveredTabOnly() async throws {
        try await withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: ["a.swift", "b.swift"])
            defer { harness.close() }
            let first = try harness.file("a.swift")
            let context = harness.context(first)
            let interaction = EditorTabInteraction()

            interaction.middleClicked(buttonNumber: EditorTabInteraction.middleButtonNumber, context)
            interaction.isHovering = true
            interaction.middleClicked(buttonNumber: 0, context)
            try await Task.sleep(for: .milliseconds(150))
            #expect(harness.editor.tabs.count == 2)

            interaction.middleClicked(buttonNumber: EditorTabInteraction.middleButtonNumber, context)
            try await eventually(timeout: .seconds(2)) {
                harness.editor.tabs.map(\.file.name) == ["b.swift"]
            }
        }
    }

    @Test
    func monitoredEventsPassThroughUnchanged() async throws {
        try await withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: ["a.swift", "b.swift"])
            defer { harness.close() }
            let event = try #require(
                NSEvent.mouseEvent(
                    with: .otherMouseDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: 0,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: 1
                )
            )
            let interaction = EditorTabInteraction()
            interaction.isHovering = true

            let first = try harness.file("a.swift")
            let context = harness.context(first)
            let returned = interaction.monitored(event, context)

            #expect(returned === event)
            try await Task.sleep(for: .milliseconds(100))
            #expect(harness.editor.tabs.count == 2)
        }
    }

    @Test
    func aMiddleClickWhileHoveringTheHostedTabClosesItThroughTheLocalMonitor() async throws {
        try await withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: ["a.swift", "b.swift"])
            defer { harness.close() }
            let first = try harness.file("a.swift")
            let interaction = EditorTabInteraction()
            let hosted = try hostTab(harness, file: first, interaction: interaction)
            defer { hosted.close() }
            try await hosted.settle()
            interaction.isHovering = true
            let cgEvent = try #require(
                CGEvent(
                    mouseEventSource: nil,
                    mouseType: .otherMouseDown,
                    mouseCursorPosition: .zero,
                    mouseButton: .center
                )
            )
            let event = try #require(NSEvent(cgEvent: cgEvent))

            NSApp.sendEvent(event)

            try await eventually(timeout: .seconds(30)) {
                harness.editor.tabs.map(\.file.name) == ["b.swift"]
            }
        }
    }

    @Test
    func focusedAndUnfocusedActiveTabsRenderDifferently() async throws {
        try await withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: ["One.swift"])
            defer { harness.close() }
            let file = harness.files[0]
            let focused = try hostTab(harness, file: file, focused: true)
            defer { focused.close() }
            let unfocused = try hostTab(harness, file: file, focused: false)
            defer { unfocused.close() }
            try await focused.settle()
            try await unfocused.settle()

            #expect(focused.renders())
            #expect(unfocused.renders())
            #expect(HostedView.pixelsDiffer(focused.snapshot(), unfocused.snapshot()))
        }
    }

    @Test
    func activeTestFilesGetTheTestFileBackgroundWhichDimsWhenUnfocused() async throws {
        try await withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: ["Case.test.ts", "Plain.ts"])
            defer { harness.close() }
            let testFile = try harness.file("Case.test.ts")
            harness.editor.setSelectedTab(testFile)
            let focused = try hostTab(harness, file: testFile, focused: true)
            defer { focused.close() }
            let unfocused = try hostTab(harness, file: testFile, focused: false)
            defer { unfocused.close() }
            try await focused.settle()
            try await unfocused.settle()

            #expect(HostedView.pixelsDiffer(focused.snapshot(), unfocused.snapshot()))
        }
    }

    @Test
    func hoveredPressedAndDraggedInactiveTabsShowTheRoundedHoverBackground() async throws {
        try await withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: ["a.swift", "b.swift"])
            defer { harness.close() }
            let inactive = try harness.file("a.swift")
            let interaction = EditorTabInteraction()
            let hosted = try hostTab(harness, file: inactive, interaction: interaction)
            defer { hosted.close() }
            try await hosted.settle()
            let resting = hosted.snapshot()

            interaction.isHovering = true
            try await hosted.settle()
            let hovering = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(resting, hovering))

            interaction.isHovering = false
            interaction.pressBegan()
            try await hosted.settle()
            #expect(HostedView.pixelsDiffer(resting, hosted.snapshot()))

            let dragged = try hostTab(harness, file: inactive, dragging: inactive.id)
            defer { dragged.close() }
            try await dragged.settle()
            #expect(HostedView.pixelsDiffer(resting, dragged.snapshot()))
        }
    }

    @Test
    func temporaryTabsRenderItalic() async throws {
        try await withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: ["a.swift", "b.swift"])
            defer { harness.close() }
            let file = try harness.file("a.swift")
            let permanent = try hostTab(harness, file: file)
            defer { permanent.close() }
            try await permanent.settle()
            let before = permanent.snapshot()

            harness.editor.temporaryTab = harness.editor.tabs.first { $0.file == file }
            try await permanent.settle()

            #expect(HostedView.pixelsDiffer(before, permanent.snapshot()))
        }
    }

    @Test
    func editedDocumentsShowTheModifiedDot() async throws {
        try await withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: ["One.swift"])
            defer { harness.close() }
            let file = harness.files[0]
            let hosted = try hostTab(harness, file: file)
            defer { hosted.close() }
            try await hosted.settle()
            let clean = hosted.snapshot()
            let document = try #require(file.fileDocument)

            document.autosavingInPlace = { false }
            document.updateChangeCount(.changeDone)
            try await hosted.settle()

            #expect(document.isDocumentEdited)
            #expect(HostedView.pixelsDiffer(clean, hosted.snapshot()))
            document.updateChangeCount(.changeCleared)
        }
    }
}
