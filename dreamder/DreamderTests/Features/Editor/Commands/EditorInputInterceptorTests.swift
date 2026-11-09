import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Testing
@testable import Dreamder

@MainActor
final class MenuKeyRecorder {
    private(set) var events: [NSEvent] = []

    func record(_ event: NSEvent) -> Bool {
        events.append(event)
        return true
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct EditorInputInterceptorTests {
    private static let slashKeyCode: UInt16 = 44
    private static let openBracketKeyCode: UInt16 = 33
    private static let closeBracketKeyCode: UInt16 = 30
    private static let dKeyCode: UInt16 = 2

    @MainActor
    private struct Session {
        let fixture: HostedSourceEditorFixture
        let hosted: HostedSourceEditor
        let controller: TextViewController
        let textView: TextView
        let coordinator: EditorActionCoordinator
        let interceptor: EditorInputInterceptor
        let recorder: MenuKeyRecorder

        var window: NSWindow {
            hosted.window
        }

        var selections: [NSRange] {
            textView.selectionManager.textSelections.map(\.range).sorted { $0.location < $1.location }
        }

        static func open(in directory: URL, markup: String) async throws -> Self {
            let parsed = EditorMarkup(markup)
            let recorder = MenuKeyRecorder()
            let interceptor = EditorInputInterceptor(performMenuKeyEquivalent: { recorder.record($0) })
            let fixture = try HostedSourceEditorFixture.make(
                in: directory,
                fileName: "Sample.txt",
                typeIdentifier: "public.plain-text",
                contents: parsed.text
            )
            let coordinator = EditorActionCoordinator(file: fixture.editorInstance.file, interceptor: interceptor)
            let hosted = fixture.host(coordinators: [coordinator], size: NSSize(width: 900, height: 600))
            try await eventually {
                hosted.controller?.textView?.window === hosted.window && coordinator.isMonitoringInput
            }
            let controller = try #require(hosted.controller)
            let textView = try #require(controller.textView)
            textView.replaceCharacters(in: NSRange(location: 0, length: textView.textStorage.length), with: parsed.text)
            textView.selectionManager.setSelectedRanges(parsed.selections)
            hosted.window.makeFirstResponder(textView)
            return Self(
                fixture: fixture,
                hosted: hosted,
                controller: controller,
                textView: textView,
                coordinator: coordinator,
                interceptor: interceptor,
                recorder: recorder
            )
        }

        func close() {
            hosted.close()
        }

        func keyEvent(
            _ characters: String,
            keyCode: UInt16,
            modifiers: NSEvent.ModifierFlags,
            type: NSEvent.EventType = .keyDown,
            in targetWindow: NSWindow? = nil
        ) throws -> NSEvent {
            try #require(
                NSEvent.keyEvent(
                    with: type,
                    location: .zero,
                    modifierFlags: modifiers,
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: (targetWindow ?? window).windowNumber,
                    context: nil,
                    characters: characters,
                    charactersIgnoringModifiers: characters,
                    isARepeat: false,
                    keyCode: keyCode
                )
            )
        }

        func mouseEvent(
            _ type: NSEvent.EventType,
            at point: NSPoint,
            modifiers: NSEvent.ModifierFlags = [.option],
            clickCount: Int = 1,
            in targetWindow: NSWindow? = nil
        ) throws -> NSEvent {
            try #require(
                NSEvent.mouseEvent(
                    with: type,
                    location: point,
                    modifierFlags: modifiers,
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: (targetWindow ?? window).windowNumber,
                    context: nil,
                    eventNumber: 1,
                    clickCount: clickCount,
                    pressure: 1
                )
            )
        }

        func click(_ type: NSEvent.EventType, at point: NSPoint) throws {
            let event = try mouseEvent(type, at: point)
            interceptor.handleMouse(event)
            if type == .leftMouseDown {
                textView.mouseDown(with: event)
            } else {
                textView.mouseUp(with: event)
            }
        }

        func clickPoint(forOffset offset: Int) -> NSPoint? {
            textView.layoutManager.layoutLines()
            textView.layoutSubtreeIfNeeded()
            guard let rect = textView.layoutManager.rectForOffset(offset) else { return nil }
            let local = NSPoint(x: rect.midX + 1, y: rect.midY)
            guard let resolved = textView.layoutManager.textOffsetAtPoint(local),
                  abs(resolved - offset) <= 1 else { return nil }
            let point = textView.convert(local, to: nil)
            return hitsTextView(at: point) ? point : nil
        }

        func windowPoint(forOffset offset: Int) throws -> NSPoint {
            try #require(clickPoint(forOffset: offset))
        }

        func centerPoint() -> NSPoint {
            textView.convert(NSPoint(x: textView.visibleRect.midX, y: textView.visibleRect.minY + 8), to: nil)
        }

        func hitsTextView(at point: NSPoint) -> Bool {
            guard let hit = window.contentView?.superview?.hitTest(point) else { return false }
            return hit === textView || hit.isDescendant(of: textView)
        }
    }

    @Test
    func commandSlashIsForwardedToTheMenuAndNeverReachesThePackage() async throws {
        try await withTempDir { directory in
            let session = try await Session.open(in: directory, markup: "let a = 1<caret>")
            defer { session.close() }

            let event = try session.keyEvent("/", keyCode: Self.slashKeyCode, modifiers: [.command])
            NSApp.sendEvent(event)

            #expect(session.recorder.events.count == 1)
            #expect(session.textView.string == "let a = 1")
        }
    }

    @Test
    func commandBracketsAreForwardedToTheMenuInsteadOfIndenting() async throws {
        try await withTempDir { directory in
            let session = try await Session.open(in: directory, markup: "alpha<caret>")
            defer { session.close() }

            NSApp.sendEvent(try session.keyEvent("]", keyCode: Self.closeBracketKeyCode, modifiers: [.command]))
            NSApp.sendEvent(try session.keyEvent("[", keyCode: Self.openBracketKeyCode, modifiers: [.command]))

            #expect(session.recorder.events.count == 2)
            #expect(session.textView.string == "alpha")
        }
    }

    @Test
    func unownedKeysModifiersAndFocusAreNotConsumed() async throws {
        try await withTempDir { directory in
            let session = try await Session.open(in: directory, markup: "alpha<caret>")
            defer { session.close() }
            let interceptor = session.interceptor

            let duplicate = try session.keyEvent("d", keyCode: Self.dKeyCode, modifiers: [.command])
            #expect(!interceptor.handleKey(duplicate))

            let shifted = try session.keyEvent("/", keyCode: Self.slashKeyCode, modifiers: [.command, .shift])
            #expect(!interceptor.handleKey(shifted))

            let flags = try session.keyEvent(
                "/",
                keyCode: Self.slashKeyCode,
                modifiers: [.command],
                type: .flagsChanged
            )
            #expect(!interceptor.handleKey(flags))

            let other = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 80, height: 60),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            other.isReleasedWhenClosed = false
            defer { other.close() }
            let foreign = try session.keyEvent("/", keyCode: Self.slashKeyCode, modifiers: [.command], in: other)
            #expect(!interceptor.handleKey(foreign))

            let owned = try session.keyEvent("/", keyCode: Self.slashKeyCode, modifiers: [.command])
            #expect(interceptor.handleKey(owned))
            session.window.makeFirstResponder(nil)
            #expect(!interceptor.handleKey(owned))

            #expect(session.recorder.events.count == 1)
        }
    }

    @Test
    func optionClickAddsACaretAndASecondClickRemovesIt() async throws {
        try await withTempDir { directory in
            let session = try await Session.open(in: directory, markup: "alpha\nbravo\ncharlie<caret>")
            defer { session.close() }
            try await eventually { session.clickPoint(forOffset: 8) != nil }
            let point = try session.windowPoint(forOffset: 8)
            session.window.makeKey()
            session.textView.selectionManager.setSelectedRanges([NSRange(location: 1, length: 0)])
            #expect(session.selections == [NSRange(location: 1, length: 0)])

            try session.click(.leftMouseDown, at: point)
            #expect(session.selections.count == 1)
            #expect(session.selections.first?.length == 0)
            #expect((6...12).contains(session.selections.first?.location ?? -1))
            try session.click(.leftMouseUp, at: point)

            let added = session.selections
            #expect(added.count == 2)
            #expect(added.first == NSRange(location: 1, length: 0))
            #expect(added.last?.length == 0)
            #expect((6...12).contains(added.last?.location ?? -1))

            try session.click(.leftMouseDown, at: point)
            try session.click(.leftMouseUp, at: point)

            #expect(session.selections == [NSRange(location: 1, length: 0)])
        }
    }

    @Test
    func optionClickWithoutDragRestoresPreviousSelectionsAndAddsTheClickedCaret() async throws {
        try await withTempDir { directory in
            let session = try await Session.open(in: directory, markup: "alpha\nbravo\ncharlie<caret>")
            defer { session.close() }
            try await eventually { session.hitsTextView(at: session.centerPoint()) }
            let point = session.centerPoint()
            let previous = [NSRange(location: 1, length: 0), NSRange(location: 3, length: 2)]
            session.textView.selectionManager.setSelectedRanges(previous)

            session.interceptor.handleMouse(try session.mouseEvent(.leftMouseDown, at: point))
            session.textView.selectionManager.setSelectedRange(NSRange(location: 8, length: 0))
            session.interceptor.handleMouse(
                try session.mouseEvent(.leftMouseDragged, at: NSPoint(x: point.x + 1, y: point.y))
            )
            session.interceptor.handleMouse(try session.mouseEvent(.leftMouseUp, at: point))

            #expect(session.selections == previous + [NSRange(location: 8, length: 0)])
        }
    }

    @Test
    func theMouseMonitorRoutesDeliveredDownAndUpEventsToTheInterceptor() async throws {
        try await withTempDir { directory in
            let session = try await Session.open(in: directory, markup: "alpha\nbravo\ncharlie<caret>")
            defer { session.close() }
            try await eventually { session.hitsTextView(at: session.centerPoint()) }
            let point = session.centerPoint()
            let previous = [NSRange(location: 1, length: 0), NSRange(location: 3, length: 2)]
            session.textView.selectionManager.setSelectedRanges(previous)

            NSApp.sendEvent(try session.mouseEvent(.leftMouseDown, at: point))
            session.textView.selectionManager.setSelectedRange(NSRange(location: 8, length: 0))
            NSApp.sendEvent(try session.mouseEvent(.leftMouseUp, at: point))

            #expect(session.selections == previous + [NSRange(location: 8, length: 0)])
        }
    }

    @Test
    func draggingAfterOptionDownKeepsTheDragSelection() async throws {
        try await withTempDir { directory in
            let session = try await Session.open(in: directory, markup: "alpha\nbravo\ncharlie<caret>")
            defer { session.close() }
            try await eventually { session.hitsTextView(at: session.centerPoint()) }
            let point = session.centerPoint()
            session.textView.selectionManager.setSelectedRanges([
                NSRange(location: 1, length: 0),
                NSRange(location: 3, length: 0)
            ])

            session.interceptor.handleMouse(try session.mouseEvent(.leftMouseDown, at: point))
            session.textView.selectionManager.setSelectedRange(NSRange(location: 8, length: 0))
            session.interceptor.handleMouse(
                try session.mouseEvent(.leftMouseDragged, at: NSPoint(x: point.x + 40, y: point.y))
            )
            session.interceptor.handleMouse(try session.mouseEvent(.leftMouseUp, at: point))

            #expect(session.selections == [NSRange(location: 8, length: 0)])
        }
    }

    @Test
    func clicksThatAreNotPlainOptionClicksInTheEditorAreIgnored() async throws {
        try await withTempDir { directory in
            let session = try await Session.open(in: directory, markup: "alpha\nbravo\ncharlie<caret>")
            defer { session.close() }
            try await eventually { session.hitsTextView(at: session.centerPoint()) }
            let point = session.centerPoint()
            let previous = [NSRange(location: 1, length: 0), NSRange(location: 3, length: 0)]
            let clicked = NSRange(location: 8, length: 0)

            @MainActor func click(
                modifiers: NSEvent.ModifierFlags = [.option],
                clickCount: Int = 1,
                in targetWindow: NSWindow? = nil
            ) throws {
                session.textView.selectionManager.setSelectedRanges(previous)
                session.interceptor.handleMouse(
                    try session.mouseEvent(
                        .leftMouseDown,
                        at: point,
                        modifiers: modifiers,
                        clickCount: clickCount,
                        in: targetWindow
                    )
                )
                session.textView.selectionManager.setSelectedRange(clicked)
                session.interceptor.handleMouse(try session.mouseEvent(.leftMouseUp, at: point))
                #expect(session.selections == [clicked])
            }

            try click(modifiers: [])
            try click(modifiers: [.option, .shift])
            try click(clickCount: 2)

            let other = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 80, height: 60),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            other.isReleasedWhenClosed = false
            defer { other.close() }
            try click(in: other)

            session.textView.isEditable = false
            try click()
        }
    }

    @Test
    func releasedClicksWithoutASingleCaretOrPendingClickChangeNothing() async throws {
        try await withTempDir { directory in
            let session = try await Session.open(in: directory, markup: "alpha\nbravo\ncharlie<caret>")
            defer { session.close() }
            try await eventually { session.hitsTextView(at: session.centerPoint()) }
            let point = session.centerPoint()
            let interceptor = session.interceptor

            interceptor.handleMouse(try session.mouseEvent(.leftMouseDragged, at: point))
            interceptor.handleMouse(try session.mouseEvent(.leftMouseUp, at: point))
            interceptor.handleMouse(try session.mouseEvent(.mouseMoved, at: point))

            session.textView.selectionManager.setSelectedRanges([NSRange(location: 1, length: 0)])
            interceptor.handleMouse(try session.mouseEvent(.leftMouseDown, at: point))
            let range = NSRange(location: 2, length: 3)
            session.textView.selectionManager.setSelectedRange(range)
            interceptor.handleMouse(try session.mouseEvent(.leftMouseUp, at: point))
            #expect(session.selections == [range])

            session.textView.selectionManager.setSelectedRanges([NSRange(location: 1, length: 0)])
            interceptor.handleMouse(try session.mouseEvent(.leftMouseDown, at: point))
            let carets = [NSRange(location: 2, length: 0), NSRange(location: 4, length: 0)]
            session.textView.selectionManager.setSelectedRanges(carets)
            interceptor.handleMouse(try session.mouseEvent(.leftMouseUp, at: point))
            #expect(session.selections == carets)
        }
    }

    @Test
    func monitorsAreInstalledOnceAndRemovedOnDestroy() async throws {
        try await withTempDir { directory in
            let session = try await Session.open(in: directory, markup: "alpha<caret>")
            defer { session.close() }
            let interceptor = session.interceptor

            #expect(interceptor.installedMonitorCount == 3)
            interceptor.installEarlyKeyMonitor()
            interceptor.installLateKeyMonitor()
            interceptor.installMouseMonitor()
            #expect(interceptor.installedMonitorCount == 3)
            #expect(session.coordinator.isMonitoringInput)

            session.coordinator.destroy()

            #expect(interceptor.installedMonitorCount == 0)
            #expect(!session.coordinator.isMonitoringInput)
            let owned = try session.keyEvent("/", keyCode: Self.slashKeyCode, modifiers: [.command])
            #expect(!interceptor.handleKey(owned))
        }
    }
}
