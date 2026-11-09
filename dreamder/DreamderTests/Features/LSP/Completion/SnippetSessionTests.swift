import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct SnippetSessionTests {
    private static let tabKeyCode: UInt16 = 48
    private static let escapeKeyCode: UInt16 = 53
    private static let returnKeyCode: UInt16 = 36

    @MainActor
    private final class Ended {
        var count = 0
    }

    @MainActor
    private struct Editor {
        let hosted: HostedSourceEditor
        let controller: TextViewController
        let textView: TextView
        let ended = Ended()

        var text: String {
            textView.string
        }

        var selection: NSRange {
            textView.selectionManager.textSelections.first?.range ?? NSRange(location: NSNotFound, length: 0)
        }

        func start(_ source: String) throws -> SnippetSession {
            let template = SnippetTemplate(parsing: source)
            let everything = NSRange(location: 0, length: textView.textStorage.length)
            textView.replaceCharacters(in: everything, with: template.text)
            (textView.undoManager as? CEUndoManager)?.clearStack()
            try focus()
            let ended = ended
            return try #require(
                SnippetSession(controller: controller, template: template, origin: 0) { ended.count += 1 }
            )
        }

        func caret(at location: Int, length: Int = 0) {
            controller.setCursorPositions([CursorPosition(range: NSRange(location: location, length: length))])
        }

        func key(
            _ keyCode: UInt16,
            modifiers: NSEvent.ModifierFlags = [],
            windowNumber: Int? = nil
        ) throws -> NSEvent {
            try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: modifiers,
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: windowNumber ?? hosted.window.windowNumber,
                    context: nil,
                    characters: "\t",
                    charactersIgnoringModifiers: "\t",
                    isARepeat: false,
                    keyCode: keyCode
                )
            )
        }

        func focus() throws {
            try #require(hosted.window.makeFirstResponder(textView))
            try #require(hosted.window.firstResponder === textView)
        }

        func tab(shift: Bool = false, focused: Bool = true) throws -> NSEvent {
            if focused {
                try focus()
            }
            return try key(SnippetSessionTests.tabKeyCode, modifiers: shift ? .shift : [])
        }

        func close() {
            hosted.close()
        }
    }

    private func open(in directory: URL) async throws -> Editor {
        let fixture = try HostedSourceEditorFixture.make(in: directory, contents: "")
        let hosted = fixture.host(coordinators: [], size: NSSize(width: 900, height: 600))
        try await eventually { hosted.controller?.textView?.window === hosted.window }
        let controller = try #require(hosted.controller)
        let textView = try #require(controller.textView)
        try await eventually {
            hosted.window.makeFirstResponder(textView) && hosted.window.firstResponder === textView
        }
        return Editor(hosted: hosted, controller: controller, textView: textView)
    }

    @Test func tabWalksThroughTheStopsAndFinishesAtTheEnd() async throws {
        try await withTempDir { directory in
            let editor = try await open(in: directory)
            defer { editor.close() }
            let session = try editor.start("foo(${1:a}, ${2:b})$0")
            #expect(editor.text == "foo(a, b)")
            #expect(editor.selection == NSRange(location: 4, length: 1))
            #expect(session.activeStopIndex == 1)
            #expect(session.isMonitoringKeyEvents)

            #expect(session.handle(try editor.tab()) == nil)
            #expect(editor.selection == NSRange(location: 7, length: 1))
            #expect(session.activeStopIndex == 2)

            #expect(session.handle(try editor.tab()) == nil)
            #expect(editor.selection == NSRange(location: 9, length: 0))
            #expect(!session.isActive)
            #expect(!session.isMonitoringKeyEvents)
            #expect(editor.ended.count == 1)
        }
    }

    @Test func tabsSentThroughTheApplicationReachTheSession() async throws {
        try await withTempDir { directory in
            let editor = try await open(in: directory)
            defer { editor.close() }
            let session = try editor.start("${1:a} ${2:b}")
            NSApp.sendEvent(try editor.tab())
            #expect(editor.selection == NSRange(location: 2, length: 1))
            #expect(session.isActive)
            NSApp.sendEvent(try editor.tab())
            #expect(!session.isActive)
            #expect(editor.text == "a b")
        }
    }

    @Test func shiftTabGoesBackAndStaysAtTheFirstStop() async throws {
        try await withTempDir { directory in
            let editor = try await open(in: directory)
            defer { editor.close() }
            let session = try editor.start("${1:a} ${2:b} ${3:c}")
            _ = session.handle(try editor.tab())
            _ = session.handle(try editor.tab())
            #expect(editor.selection == NSRange(location: 4, length: 1))

            #expect(session.handle(try editor.tab(shift: true)) == nil)
            #expect(editor.selection == NSRange(location: 2, length: 1))
            #expect(session.handle(try editor.tab(shift: true)) == nil)
            #expect(editor.selection == NSRange(location: 0, length: 1))
            #expect(session.handle(try editor.tab(shift: true)) == nil)
            #expect(editor.selection == NSRange(location: 0, length: 1))
            #expect(session.isActive)
        }
    }

    @Test func mirroredPlaceholdersUpdateTogetherAndUndoRevertsBothAtOnce() async throws {
        try await withTempDir { directory in
            let editor = try await open(in: directory)
            defer { editor.close() }
            let session = try editor.start("${1:x} = $1;")
            #expect(editor.text == "x = x;")

            editor.textView.insertText("ab")
            #expect(editor.text == "ab = ab;")
            #expect(editor.selection == NSRange(location: 2, length: 0))
            editor.textView.insertText("c")
            #expect(editor.text == "abc = abc;")
            #expect(editor.selection == NSRange(location: 3, length: 0))
            #expect(session.isActive)

            editor.textView.undoManager?.undo()
            #expect(editor.text == "ab = ab;")
            #expect(!session.isActive)
        }
    }

    @Test func editingAMirrorUpdatesThePrimaryPlaceholder() async throws {
        try await withTempDir { directory in
            let editor = try await open(in: directory)
            defer { editor.close() }
            let session = try editor.start("${1:x} = $1;")
            editor.caret(at: 5)
            #expect(session.isActive)
            editor.textView.insertText("y")
            #expect(editor.text == "xy = xy;")
            #expect(editor.selection == NSRange(location: 7, length: 0))
            #expect(session.isActive)
        }
    }

    @Test func retypingTheSameTextLeavesTheMirrorsUntouched() async throws {
        try await withTempDir { directory in
            let editor = try await open(in: directory)
            defer { editor.close() }
            let session = try editor.start("${1:x} = $1;")
            editor.textView.insertText("x")
            #expect(editor.text == "x = x;")
            #expect(session.isActive)
        }
    }

    @Test func escapeEndsTheSessionAndKeepsTheText() async throws {
        try await withTempDir { directory in
            let editor = try await open(in: directory)
            defer { editor.close() }
            let session = try editor.start("foo(${1:a})")
            let escape = try editor.key(Self.escapeKeyCode)
            #expect(session.handle(escape) == nil)
            #expect(!session.isActive)
            #expect(editor.text == "foo(a)")
            #expect(editor.ended.count == 1)

            let tab = try editor.tab()
            #expect(session.handle(tab) === tab)
            session.cancel()
            #expect(editor.ended.count == 1)
        }
    }

    @Test func typingOutsideTheActiveStopEndsTheSession() async throws {
        try await withTempDir { directory in
            let editor = try await open(in: directory)
            defer { editor.close() }
            let session = try editor.start("foo(${1:a})")
            editor.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "x")
            #expect(!session.isActive)
            #expect(editor.text == "xfoo(a)")
        }
    }

    @Test func movingTheCaretOutsideTheActiveStopEndsTheSession() async throws {
        try await withTempDir { directory in
            let editor = try await open(in: directory)
            defer { editor.close() }
            let session = try editor.start("foo(${1:abc})")
            editor.caret(at: 5)
            #expect(session.isActive)
            editor.caret(at: 7)
            #expect(session.isActive)
            editor.caret(at: 8)
            #expect(!session.isActive)
            #expect(editor.ended.count == 1)
        }
    }

    @Test func multipleSelectionsEndTheSession() async throws {
        try await withTempDir { directory in
            let editor = try await open(in: directory)
            defer { editor.close() }
            let session = try editor.start("foo(${1:abc})")
            editor.controller.setCursorPositions([
                CursorPosition(range: NSRange(location: 5, length: 0)),
                CursorPosition(range: NSRange(location: 6, length: 0))
            ])
            #expect(!session.isActive)
        }
    }

    @Test func choicesInsertTheFirstOption() async throws {
        try await withTempDir { directory in
            let editor = try await open(in: directory)
            defer { editor.close() }
            let session = try editor.start("${1|public,private|} func")
            #expect(editor.text == "public func")
            #expect(editor.selection == NSRange(location: 0, length: 6))
            #expect(session.activeStopIndex == 1)
        }
    }

    @Test func nestedPlaceholdersAreEditableAndGrowTheirParent() async throws {
        try await withTempDir { directory in
            let editor = try await open(in: directory)
            defer { editor.close() }
            let session = try editor.start("${1:foo ${2:bar}} end")
            #expect(editor.selection == NSRange(location: 0, length: 7))
            _ = session.handle(try editor.tab())
            #expect(editor.selection == NSRange(location: 4, length: 3))
            #expect(session.activeStopIndex == 2)
            editor.textView.insertText("X")
            #expect(editor.text == "foo X end")
            _ = session.handle(try editor.tab())
            #expect(!session.isActive)
            #expect(editor.selection == NSRange(location: 9, length: 0))
        }
    }

    @Test func replacingAParentRemovesItsNestedStops() async throws {
        try await withTempDir { directory in
            let editor = try await open(in: directory)
            defer { editor.close() }
            let session = try editor.start("${1:foo ${2:bar}} end")
            editor.textView.insertText("Z")
            #expect(editor.text == "Z end")
            _ = session.handle(try editor.tab())
            #expect(!session.isActive)
            #expect(editor.selection == NSRange(location: 5, length: 0))
        }
    }

    @Test func undoEndsTheSession() async throws {
        try await withTempDir { directory in
            let editor = try await open(in: directory)
            defer { editor.close() }
            let session = try editor.start("foo(${1:a})")
            editor.textView.insertText("b")
            #expect(session.isActive)
            editor.textView.undoManager?.undo()
            #expect(!session.isActive)
            #expect(editor.text == "foo(a)")
        }
    }

    @Test func redoEndsTheSession() async throws {
        try await withTempDir { directory in
            let editor = try await open(in: directory)
            defer { editor.close() }
            let first = try editor.start("foo(${1:a})")
            editor.textView.insertText("b")
            editor.textView.undoManager?.undo()
            #expect(!first.isActive)
            #expect(editor.text == "foo(a)")

            let ended = Ended()
            let second = try #require(
                SnippetSession(
                    controller: editor.controller,
                    template: SnippetTemplate(parsing: "${1:a}"),
                    origin: 4
                ) { ended.count += 1 }
            )
            #expect(second.isActive)
            editor.textView.undoManager?.redo()
            #expect(!second.isActive)
            #expect(ended.count == 1)
            #expect(editor.text == "foo(b)")
        }
    }

    @Test func everyMirrorFollowsTheEditedPlaceholder() async throws {
        try await withTempDir { directory in
            let editor = try await open(in: directory)
            defer { editor.close() }
            let session = try editor.start("${1:x} $1 $1;")
            #expect(editor.text == "x x x;")
            editor.textView.insertText("ab")
            #expect(editor.text == "ab ab ab;")
            #expect(editor.selection == NSRange(location: 2, length: 0))
            #expect(session.isActive)
            editor.textView.insertText("c")
            #expect(editor.text == "abc abc abc;")
            #expect(session.isActive)
        }
    }

    @Test func aMirrorThatCannotBeUpdatedEndsTheSession() async throws {
        try await withTempDir { directory in
            let editor = try await open(in: directory)
            defer { editor.close() }
            let session = try editor.start("${1:x} = $1;")
            editor.textView.isEditable = false
            editor.textView.textStorage.replaceCharacters(in: NSRange(location: 0, length: 1), with: "ab")
            editor.caret(at: 1)
            #expect(!session.isActive)
            #expect(editor.ended.count == 1)
            #expect(editor.text == "ab = x;")
        }
    }

    @Test func eventsThatAreNotMeantForTheSessionPassThrough() async throws {
        try await withTempDir { directory in
            let editor = try await open(in: directory)
            defer { editor.close() }
            let session = try editor.start("foo(${1:a})")

            let command = try editor.key(Self.tabKeyCode, modifiers: .command)
            #expect(session.handle(command) === command)
            let shiftEscape = try editor.key(Self.escapeKeyCode, modifiers: .shift)
            #expect(session.handle(shiftEscape) === shiftEscape)
            let enter = try editor.key(Self.returnKeyCode)
            #expect(session.handle(enter) === enter)
            let foreign = try editor.key(Self.tabKeyCode, windowNumber: 0)
            #expect(session.handle(foreign) === foreign)

            editor.hosted.window.makeFirstResponder(nil)
            let unfocused = try editor.tab(focused: false)
            #expect(session.handle(unfocused) === unfocused)
            #expect(session.isActive)
        }
    }

    @Test func templatesWithoutStopsNeverStartASession() async throws {
        try await withTempDir { directory in
            let editor = try await open(in: directory)
            defer { editor.close() }
            let session = SnippetSession(
                controller: editor.controller,
                template: SnippetTemplate(parsing: "plain"),
                origin: 0
            ) {}
            #expect(session == nil)
        }
    }

    @Test func aReleasedSessionRemovesItsMonitor() async throws {
        try await withTempDir { directory in
            let editor = try await open(in: directory)
            defer { editor.close() }
            let template = SnippetTemplate(parsing: "foo(${1:a})")
            editor.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: template.text)
            var session: SnippetSession? = SnippetSession(
                controller: editor.controller,
                template: template,
                origin: 0
            ) {}
            #expect(session?.isMonitoringKeyEvents == true)
            session = nil
            #expect(session == nil)
        }
    }
}
