import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized)
struct MarkdownTypingCoordinatorTests {
    private static let returnKeyCode: UInt16 = 36
    private static let deleteKeyCode: UInt16 = 51

    @MainActor
    private struct Session {
        let hosted: HostedSourceEditor
        let controller: TextViewController
        let textView: TextView
        let coordinator: MarkdownTypingCoordinator

        var window: NSWindow {
            hosted.window
        }

        var text: String {
            textView.string
        }

        var selections: [NSRange] {
            textView.selectionManager.textSelections.map(\.range)
        }

        func reset(_ marked: String) {
            let markup = MarkdownCaretMarkup(marked)
            textView.replaceCharacters(in: NSRange(location: 0, length: textView.textStorage.length), with: markup.text)
            controller.setCursorPositions([CursorPosition(range: NSRange(location: markup.caret, length: 0))])
            window.makeFirstResponder(textView)
        }

        func close() {
            hosted.close()
        }

        func event(
            _ keyCode: UInt16,
            characters: String,
            modifiers: NSEvent.ModifierFlags = [],
            in targetWindow: NSWindow? = nil
        ) throws -> NSEvent {
            try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
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

        func returnKey(modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try event(MarkdownTypingCoordinatorTests.returnKeyCode, characters: "\r", modifiers: modifiers)
        }

        func deleteKey() throws -> NSEvent {
            try event(MarkdownTypingCoordinatorTests.deleteKeyCode, characters: "\u{7f}")
        }
    }

    private func open(
        in directory: URL,
        fileName: String = "Note.md",
        contents: String = ""
    ) async throws -> Session {
        let fixture = try HostedSourceEditorFixture.make(
            in: directory,
            fileName: fileName,
            typeIdentifier: "public.plain-text",
            contents: contents
        )
        let coordinator = MarkdownTypingCoordinator(codeFile: fixture.document)
        let hosted = fixture.host(coordinators: [coordinator], size: NSSize(width: 900, height: 600))
        try await eventually { hosted.controller?.textView != nil && coordinator.isMonitoringKeyEvents }
        let controller = try #require(hosted.controller)
        let textView = try #require(controller.textView)
        hosted.window.makeFirstResponder(textView)
        return Session(hosted: hosted, controller: controller, textView: textView, coordinator: coordinator)
    }

    @Test
    func returnSentThroughTheApplicationContinuesTheList() async throws {
        try await withTempDir { directory in
            let session = try await open(in: directory)
            defer { session.close() }
            session.reset("- item<caret>")
            let event = try session.returnKey()
            NSApp.sendEvent(event)
            #expect(session.text == "- item\n- ")
            #expect(session.selections == [NSRange(location: 9, length: 0)])
        }
    }

    @Test
    func returnOnAPlainParagraphIsHandledByTheEditor() async throws {
        try await withTempDir { directory in
            let session = try await open(in: directory)
            defer { session.close() }
            session.reset("plain<caret>")
            let event = try session.returnKey()
            session.hosted.window.sendEvent(event)
            #expect(session.text == "plain\n")
            #expect(session.selections == [NSRange(location: 6, length: 0)])
        }
    }

    @Test
    func handledKeysAreConsumedAndUnhandledOnesAreReturned() async throws {
        try await withTempDir { directory in
            let session = try await open(in: directory)
            defer { session.close() }

            session.reset("- item<caret>")
            let handled = try session.returnKey()
            #expect(session.coordinator.handle(handled) == nil)
            #expect(session.text == "- item\n- ")
            #expect(session.selections == [NSRange(location: 9, length: 0)])

            session.reset("plain<caret>")
            let unhandled = try session.returnKey()
            #expect(session.coordinator.handle(unhandled) === unhandled)
            #expect(session.text == "plain")
        }
    }

    @Test
    func shiftReturnStartsAContinuationLine() async throws {
        try await withTempDir { directory in
            let session = try await open(in: directory)
            defer { session.close() }
            session.reset("- it<caret>em")
            let event = try session.returnKey(modifiers: .shift)
            #expect(session.coordinator.handle(event) == nil)
            #expect(session.text == "- item\n  ")
            #expect(session.selections == [NSRange(location: 9, length: 0)])
        }
    }

    @Test
    func otherModifiersAreLeftToTheEditor() async throws {
        try await withTempDir { directory in
            let session = try await open(in: directory)
            defer { session.close() }
            session.reset("- item<caret>")
            for modifiers: NSEvent.ModifierFlags in [.command, .option, .control, [.shift, .command]] {
                let event = try session.returnKey(modifiers: modifiers)
                #expect(session.coordinator.handle(event) === event)
            }
            #expect(session.text == "- item")
        }
    }

    @Test
    func backspaceAfterTheMarkerRemovesTheMarker() async throws {
        try await withTempDir { directory in
            let session = try await open(in: directory)
            defer { session.close() }
            session.reset("- <caret>item")
            let event = try session.deleteKey()
            #expect(session.coordinator.handle(event) == nil)
            #expect(session.text == "item")
            #expect(session.selections == [NSRange(location: 0, length: 0)])
        }
    }

    @Test
    func backspaceInsideTheIndentUnindentsTheItem() async throws {
        try await withTempDir { directory in
            let session = try await open(in: directory)
            defer { session.close() }
            session.reset("- a\n  <caret>- b")
            let event = try session.deleteKey()
            #expect(session.coordinator.handle(event) == nil)
            #expect(session.text == "- a\n- b")
            #expect(session.selections == [NSRange(location: 4, length: 0)])
        }
    }

    @Test
    func ordinaryBackspaceIsLeftToTheEditor() async throws {
        try await withTempDir { directory in
            let session = try await open(in: directory)
            defer { session.close() }
            session.reset("- ite<caret>m")
            let event = try session.deleteKey()
            #expect(session.coordinator.handle(event) === event)
            #expect(session.text == "- item")
        }
    }

    @Test
    func blockQuoteReturnRepeatsTheQuoteMarker() async throws {
        try await withTempDir { directory in
            let session = try await open(in: directory)
            defer { session.close() }
            session.reset("> quote<caret>")
            let event = try session.returnKey()
            #expect(session.coordinator.handle(event) == nil)
            #expect(session.text == "> quote\n> ")
            #expect(session.selections == [NSRange(location: 10, length: 0)])
        }
    }

    @Test
    func emptyItemReturnLeavesTheListInOneUndoStep() async throws {
        try await withTempDir { directory in
            let session = try await open(in: directory)
            defer { session.close() }
            session.reset("- a\n- <caret>")
            let event = try session.returnKey()
            #expect(session.coordinator.handle(event) == nil)
            #expect(session.text == "- a\n")
            #expect(session.selections == [NSRange(location: 4, length: 0)])
            session.textView.undoManager?.undo()
            #expect(session.text == "- a\n- ")
        }
    }

    @Test
    func eventsForOtherWindowsAreIgnored() async throws {
        try await withTempDir { directory in
            let session = try await open(in: directory)
            defer { session.close() }
            let other = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            other.isReleasedWhenClosed = false
            defer { other.close() }
            session.reset("- item<caret>")
            let event = try session.event(Self.returnKeyCode, characters: "\r", in: other)
            #expect(session.coordinator.handle(event) === event)
            #expect(session.text == "- item")
        }
    }

    @Test
    func eventsAreIgnoredWhileTheTextViewIsNotFirstResponder() async throws {
        try await withTempDir { directory in
            let session = try await open(in: directory)
            defer { session.close() }
            session.reset("- item<caret>")
            session.window.makeFirstResponder(nil)
            let event = try session.returnKey()
            #expect(session.coordinator.handle(event) === event)
            #expect(session.text == "- item")
        }
    }

    @Test
    func selectionsAndMultipleCaretsAreLeftToTheEditor() async throws {
        try await withTempDir { directory in
            let session = try await open(in: directory)
            defer { session.close() }
            session.reset("- one\n- two")

            session.controller.setCursorPositions([CursorPosition(range: NSRange(location: 2, length: 3))])
            let selected = try session.returnKey()
            #expect(session.coordinator.handle(selected) === selected)

            session.controller.setCursorPositions([
                CursorPosition(range: NSRange(location: 5, length: 0)),
                CursorPosition(range: NSRange(location: 11, length: 0))
            ])
            let multiple = try session.returnKey()
            #expect(session.coordinator.handle(multiple) === multiple)
            #expect(session.text == "- one\n- two")
        }
    }

    @Test
    func onlyReturnAndDeleteAreHandled() async throws {
        try await withTempDir { directory in
            let session = try await open(in: directory)
            defer { session.close() }
            session.reset("- item<caret>")
            let event = try session.event(0, characters: "a")
            #expect(session.coordinator.handle(event) === event)
            let tab = try session.event(48, characters: "\t")
            #expect(session.coordinator.handle(tab) === tab)
            #expect(session.text == "- item")
        }
    }

    @Test
    func nonMarkdownFilesAreLeftToTheEditor() async throws {
        try await withTempDir { directory in
            let session = try await open(in: directory, fileName: "Code.swift")
            defer { session.close() }
            session.reset("- item<caret>")
            let event = try session.returnKey()
            #expect(session.coordinator.handle(event) === event)
            #expect(session.text == "- item")
        }
    }

    @Test
    func settingsSwitchTheSmartBehaviorOff() async throws {
        try await withTempDir { directory in
            let session = try await open(in: directory)
            defer { session.close() }
            session.coordinator.settings.smartEnterAndBackspace = false
            session.reset("- item<caret>")
            let event = try session.returnKey()
            #expect(session.coordinator.handle(event) === event)
            #expect(session.text == "- item")
        }
    }

    @Test
    func monitorFollowsTheControllerLifecycle() async throws {
        try await withTempDir { directory in
            let session = try await open(in: directory)
            defer { session.close() }
            #expect(session.coordinator.isMonitoringKeyEvents)
            session.coordinator.controllerDidDisappear(controller: session.controller)
            #expect(!session.coordinator.isMonitoringKeyEvents)
            session.coordinator.controllerDidAppear(controller: session.controller)
            #expect(session.coordinator.isMonitoringKeyEvents)
            session.coordinator.destroy()
            #expect(!session.coordinator.isMonitoringKeyEvents)
        }
    }
}
