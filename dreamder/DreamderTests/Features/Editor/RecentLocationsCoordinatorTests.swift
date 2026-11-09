import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
private final class RecentLocationsMouseFlag {
    var pressed = false
}

@MainActor
@Suite(.serialized, .uiGate)
struct RecentLocationsCoordinatorTests {
    private static let source = (1...30).map { "let value\($0) = \($0)" }.joined(separator: "\n") + "\n"

    @MainActor
    private struct Session {
        let workspace: WorkspaceDocument
        let fixture: HostedSourceEditorFixture
        let hosted: HostedSourceEditor
        let coordinator: RecentLocationsCoordinator
        let tracker: RecentLocationsTracker
        let controller: TextViewController
        let textView: TextView
        let mouse: RecentLocationsMouseFlag

        var fileURL: URL { fixture.editorInstance.file.url }

        func close() {
            hosted.close()
            workspace.close()
        }

        func lineStart(_ line: Int) throws -> Int {
            try #require(textView.layoutManager.textLineForIndex(line - 1)).range.location
        }

        func moveCaret(to offset: Int) async throws {
            controller.setCursorPositions([CursorPosition(range: NSRange(location: offset, length: 0))])
            try await eventually { controller.cursorPositions.first?.range.location == offset }
        }

        func clickPoint(forOffset offset: Int) -> NSPoint? {
            guard let rect = textView.layoutManager.rectForOffset(offset) else { return nil }
            let point = textView.convert(NSPoint(x: rect.midX + 1, y: rect.midY), to: nil)
            guard let hit = hosted.window.contentView?.superview?.hitTest(point) else { return nil }
            return hit === textView || hit.isDescendant(of: textView) ? point : nil
        }

        func mouse(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) throws -> NSEvent {
            try #require(
                NSEvent.mouseEvent(
                    with: type,
                    location: point,
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 1,
                    clickCount: 1,
                    pressure: 1
                )
            )
        }

        func place(line: Int, column: Int) -> EditorPlace {
            EditorPlace(fileURL: fileURL, line: line, column: column)
        }
    }

    private func makeSession(
        in directory: URL,
        hasWorkspace: Bool = true,
        injectsMouse: Bool = true
    ) async throws -> Session {
        let fixture = try HostedSourceEditorFixture.make(in: directory, contents: Self.source)
        let workspace = try HostedViewFixture.makeWorkspace(in: directory)
        let mouse = RecentLocationsMouseFlag()
        var isMousePress: (@MainActor () -> Bool)?
        if injectsMouse {
            isMousePress = { @MainActor in mouse.pressed }
        }
        let coordinator = RecentLocationsCoordinator(
            editorInstance: fixture.editorInstance,
            codeFile: fixture.document,
            workspaceProvider: { hasWorkspace ? workspace : nil },
            isMousePress: isMousePress
        )
        let hosted = fixture.host(coordinators: [coordinator], size: NSSize(width: 900, height: 600))
        try await eventually { hosted.controller?.textView?.window === hosted.window }
        let controller = try #require(hosted.controller)
        return Session(
            workspace: workspace,
            fixture: fixture,
            hosted: hosted,
            coordinator: coordinator,
            tracker: RecentLocationsStore.shared.history(for: workspace),
            controller: controller,
            textView: controller.textView,
            mouse: mouse
        )
    }

    @Test
    func editsRecordChangePlacesAtTheCaretAfterTheEdit() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(in: directory)
            defer { session.close() }

            session.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "x")

            #expect(session.tracker.history.changePlaces == [session.place(line: 1, column: 2)])
        }
    }

    @Test
    func multiLineInsertionsLandAfterTheInsertedText() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(in: directory)
            defer { session.close() }
            let offset = try session.lineStart(3)

            session.textView.replaceCharacters(in: NSRange(location: offset, length: 0), with: "A\nBC")

            #expect(session.tracker.history.changePlaces == [session.place(line: 4, column: 3)])
        }
    }

    @Test
    func editsOnNearbyLinesMergeIntoOneChangePlace() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(in: directory)
            defer { session.close() }

            session.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "x")
            session.textView.replaceCharacters(in: NSRange(location: 1, length: 0), with: "y")
            let farOffset = try session.lineStart(20)
            session.textView.replaceCharacters(in: NSRange(location: farOffset, length: 0), with: "z")

            #expect(session.tracker.history.changePlaces == [
                session.place(line: 1, column: 3),
                session.place(line: 20, column: 2)
            ])
        }
    }

    @Test
    func editsAtAnInvalidOffsetAreIgnored() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(in: directory)
            defer { session.close() }

            let range = NSRange(location: 100_000, length: 0)
            session.coordinator.textView(session.textView, willReplaceContentsIn: range, with: "x")
            session.coordinator.textView(session.textView, didReplaceContentsIn: range, with: "x")

            #expect(session.tracker.history.changePlaces.isEmpty)
        }
    }

    @Test
    func mousePressesRecordThePlaceTheCaretLeft() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(in: directory)
            defer { session.close() }
            session.mouse.pressed = true

            try await session.moveCaret(to: try session.lineStart(20))

            #expect(session.tracker.history.backPlaces == [session.place(line: 1, column: 1)])

            try await session.moveCaret(to: try session.lineStart(20) + 3)
            #expect(session.tracker.history.backPlaces == [session.place(line: 1, column: 1)])

            try await session.moveCaret(to: try session.lineStart(2))
            #expect(session.tracker.history.backPlaces.map(\.line) == [1, 20])
        }
    }

    @Test
    func caretMovesWithoutAMousePressAreNotNavigation() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(in: directory)
            defer { session.close() }

            try await session.moveCaret(to: try session.lineStart(20))

            #expect(session.tracker.history.backPlaces.isEmpty)
        }
    }

    @Test
    func caretMovesAfterAClickInTheEditorWindowRecordNavigationByDefault() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(in: directory, injectsMouse: false)
            defer { session.close() }
            try await eventually { session.clickPoint(forOffset: 3) != nil }
            let point = try #require(session.clickPoint(forOffset: 3))
            session.hosted.window.makeKey()

            NSApp.sendEvent(try session.mouse(.leftMouseDown, at: point, in: session.hosted.window))
            try await session.moveCaret(to: try session.lineStart(20))
            NSApp.sendEvent(try session.mouse(.leftMouseUp, at: point, in: session.hosted.window))

            #expect(session.tracker.history.backPlaces.map(\.line) == [1])
        }
    }

    @Test
    func caretMovesAfterAClickInAnotherWindowAreNotNavigation() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(in: directory, injectsMouse: false)
            defer { session.close() }
            let other = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 80, height: 60),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            other.isReleasedWhenClosed = false
            defer { other.close() }

            NSApp.sendEvent(try session.mouse(.leftMouseDown, at: NSPoint(x: 10, y: 10), in: other))
            try await session.moveCaret(to: try session.lineStart(20))

            #expect(session.tracker.history.backPlaces.isEmpty)
        }
    }

    @Test
    func coordinatorsWithoutAWorkspaceRecordNothing() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(in: directory, hasWorkspace: false)
            defer { session.close() }
            session.mouse.pressed = true

            session.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "x")
            try await session.moveCaret(to: try session.lineStart(20))

            #expect(session.tracker.history.changePlaces.isEmpty)
            #expect(session.tracker.history.backPlaces.isEmpty)
        }
    }

    @Test
    func destroyStopsRecording() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(in: directory)
            defer { session.close() }
            session.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "x")
            #expect(session.tracker.history.changePlaces.count == 1)

            session.coordinator.destroy()
            session.mouse.pressed = true
            session.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "q")
            try await session.moveCaret(to: try session.lineStart(20))

            #expect(session.tracker.history.changePlaces.count == 1)
            #expect(session.tracker.history.backPlaces.isEmpty)
        }
    }

    @Test
    func defaultsFindTheWorkspaceOfTheDocumentAndIgnoreNonMouseEvents() async throws {
        try await withTempDir { directory in
            let fixture = try HostedSourceEditorFixture.make(in: directory, contents: Self.source)
            let workspace = try HostedSourceEditorFixture.registerWorkspace(at: directory)
            defer { workspace.close() }
            let coordinator = RecentLocationsCoordinator(editorInstance: fixture.editorInstance, codeFile: fixture.document)
            let hosted = fixture.host(coordinators: [coordinator], size: NSSize(width: 900, height: 600))
            defer { hosted.close() }
            try await eventually { hosted.controller?.textView?.window === hosted.window }
            let controller = try #require(hosted.controller)
            let tracker = RecentLocationsStore.shared.history(for: workspace)

            controller.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "x")
            controller.setCursorPositions([CursorPosition(range: NSRange(location: 40, length: 0))])
            try await eventually { controller.cursorPositions.first?.range.location == 40 }

            #expect(tracker.history.changePlaces.count == 1)
            #expect(tracker.history.backPlaces.isEmpty)
        }
    }

    @Test
    func defaultsWithoutAMatchingWorkspaceRecordNothing() async throws {
        try await withTempDir { directory in
            let fixture = try HostedSourceEditorFixture.make(in: directory, contents: Self.source)
            let coordinator = RecentLocationsCoordinator(editorInstance: fixture.editorInstance, codeFile: fixture.document)
            let hosted = fixture.host(coordinators: [coordinator], size: NSSize(width: 900, height: 600))
            defer { hosted.close() }
            try await eventually { hosted.controller?.textView?.window === hosted.window }
            let controller = try #require(hosted.controller)

            controller.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "x")
            controller.setCursorPositions([CursorPosition(range: NSRange(location: 40, length: 0))])
            try await eventually { controller.cursorPositions.first?.range.location == 40 }

            #expect(controller.textView.string.hasPrefix("xlet"))
        }
    }
}
