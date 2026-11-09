import AppKit
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct MergeConflictsWindowCoverageTests {
    private func makeController(
        _ root: URL
    ) async throws -> (controller: MergeConflictsWindowController, model: MergeConflictsViewModel) {
        let document = WorkspaceDocument()
        document.sourceControlManager = SourceControlManager(workspaceURL: root, editorManager: EditorManager())
        let model = try #require(MergeConflictsViewModel(workspace: document))
        try await eventually { model.entries.count == 2 }
        return (MergeConflictsWindowController(model: model), model)
    }

    private func makeParent(centeredOn screen: NSScreen) -> NSWindow {
        let parent = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        parent.isReleasedWhenClosed = false
        let size = parent.frame.size
        parent.setFrame(
            NSRect(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.midY - size.height / 2,
                width: size.width,
                height: size.height
            ),
            display: false
        )
        return parent
    }

    @Test
    func windowIsAClosableResizableDarkConflictsWindow() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let (controller, model) = try await makeController(dir)
            let window = try #require(controller.window)

            #expect(controller.model === model)
            #expect(window.title == "Conflicts")
            #expect(window.appearance?.name == .darkAqua)
            #expect(window.styleMask.contains(.closable))
            #expect(window.styleMask.contains(.resizable))
            #expect(window.styleMask.contains(.miniaturizable))
            #expect(window.isReleasedWhenClosed == false)
            #expect(window.contentMinSize == NSSize(width: 640, height: 300))
            #expect(window.delegate === controller)
            #expect(window.contentRect(forFrameRect: window.frame).size == NSSize(width: 900, height: 420))
        }
    }

    @Test
    func controllerCannotBeDecoded() throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: NSString(string: "x"), requiringSecureCoding: false)
        let decoder = try NSKeyedUnarchiver(forReadingFrom: data)
        #expect(MergeConflictsWindowController(coder: decoder) == nil)
    }

    @Test
    func placeCentersTheWindowOnItsParent() async throws {
        guard let screen = NSScreen.main else { return }
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let (controller, _) = try await makeController(dir)
            let window = try #require(controller.window)
            let parent = makeParent(centeredOn: screen)

            controller.place(relativeTo: parent)

            #expect(abs(window.frame.midX - parent.frame.midX) < 1)
            #expect(abs(window.frame.midY - parent.frame.midY) < 1)
        }
    }

    @Test
    func placeWithoutAParentCentersTheWindowOnTheMainScreen() async throws {
        guard let screen = NSScreen.main else { return }
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let (controller, _) = try await makeController(dir)
            let window = try #require(controller.window)

            controller.place(relativeTo: nil)

            #expect(abs(window.frame.midX - screen.visibleFrame.midX) < 1)
            #expect(abs(window.frame.midY - screen.visibleFrame.midY) < 1)
        }
    }

    @Test
    func originKeepsTheWindowInsideTheVisibleArea() {
        let size = NSSize(width: 900, height: 450)
        let visible = NSRect(x: 100, y: 50, width: 1600, height: 1000)

        let farLeft = MergeConflictsWindowController.origin(
            size: size,
            anchor: NSRect(x: -6000, y: -6000, width: 400, height: 300),
            visible: visible
        )
        #expect(farLeft == NSPoint(x: 112, y: 62))

        let farRight = MergeConflictsWindowController.origin(
            size: size,
            anchor: NSRect(x: 9000, y: 9000, width: 400, height: 300),
            visible: visible
        )
        #expect(farRight == NSPoint(x: 100 + 1600 - 900 - 12, y: 50 + 1000 - 450 - 12))

        let inside = MergeConflictsWindowController.origin(
            size: size,
            anchor: NSRect(x: 600, y: 400, width: 400, height: 300),
            visible: visible
        )
        #expect(inside == NSPoint(x: 800 - 450, y: 550 - 225))
    }

    @Test
    func originWithoutAnAnchorOrScreenIsTheZeroPoint() {
        let size = NSSize(width: 900, height: 450)

        #expect(MergeConflictsWindowController.origin(size: size, anchor: nil, visible: nil) == .zero)
        #expect(
            MergeConflictsWindowController.origin(
                size: size,
                anchor: nil,
                visible: NSRect(x: 0, y: 0, width: 2000, height: 1200)
            ) == NSPoint(x: 12, y: 12)
        )
        #expect(
            MergeConflictsWindowController.origin(
                size: size,
                anchor: NSRect(x: 0, y: 0, width: 400, height: 300),
                visible: nil
            ) == NSPoint(x: -250, y: -75)
        )
    }

    @Test
    func placeWithoutAWindowDoesNothing() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let (controller, _) = try await makeController(dir)
            controller.window = nil

            controller.place(relativeTo: nil)

            #expect(controller.window == nil)
        }
    }

    @Test
    func reloadPicksUpConflictsResolvedOutsideTheDialog() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.mergeConflict(in: dir)
            let (controller, model) = try await makeController(dir)
            #expect(model.entries.count == 2)

            try fixture.write("docs/notes.txt", "one\nresolved\nthree\n")
            try await fixture.run("add", "docs/notes.txt")
            controller.reload()

            try await eventually { model.entries.map(\.path) == ["app/config.txt"] }
            #expect(model.summary == "Merging branch feature into branch main")
        }
    }

    @Test
    func closingTheWindowNotifiesTheOwner() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let (controller, _) = try await makeController(dir)
            let window = try #require(controller.window)
            var closed = 0
            controller.onClose = { closed += 1 }
            window.orderFront(nil)

            window.close()
            #expect(closed == 1)

            controller.onClose = nil
            controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
            #expect(closed == 1)
        }
    }
}
