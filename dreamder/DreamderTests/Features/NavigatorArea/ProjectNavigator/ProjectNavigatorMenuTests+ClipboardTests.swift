import AppKit
import Foundation
import Testing
@testable import Dreamder

extension ProjectNavigatorMenuTests {
    private func keyEvent(
        _ character: String,
        modifiers: NSEvent.ModifierFlags,
        in harness: Harness
    ) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: harness.window.windowNumber,
                context: nil,
                characters: character,
                charactersIgnoringModifiers: character,
                isARepeat: false,
                keyCode: 0
            )
        )
    }

    @Test
    func commandVStartsAnInlineNewFileFromClipboardTextOnlyWhenTheOutlineIsFirstResponder() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            let sources = try harness.file("Sources")
            harness.select([sources])
            harness.click(sources)
            harness.pasteboard.replaceContents(withText: "pasted body")
            #expect(harness.window.makeFirstResponder(nil))
            let event = try keyEvent("v", modifiers: .command, in: harness)
            #expect(!harness.outlineView.performKeyEquivalent(with: event))
            #expect(harness.controller.pendingCreation == nil)

            #expect(harness.window.makeFirstResponder(harness.outlineView))
            #expect(harness.outlineView.performKeyEquivalent(with: event))
            #expect(harness.controller.pendingCreation?.contents == Data("pasted body".utf8))
            #expect(try harness.names(in: "Sources") == ["main.swift"])

            try harness.submitCreation("body.txt")
            #expect(try harness.contents("Sources/body.txt") == "pasted body")
        }
    }

    @Test
    func commandVPastesCopiedFilesIntoTheSelectedFolder() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let sources = try harness.file("Sources")
            harness.writeClipboard(["a.txt"], cut: false)
            harness.select([sources])
            #expect(harness.window.makeFirstResponder(harness.outlineView))

            #expect(harness.outlineView.performKeyEquivalent(with: try keyEvent("v", modifiers: .command, in: harness)))
            await harness.controller.pasteTask?.value

            #expect(harness.exists("Sources/a.txt"))
            #expect(harness.exists("a.txt"))
        }
    }

    @Test
    func commandCAndCommandXPutTheSelectionOnThePasteboard() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let first = try harness.file("a.txt")
            let second = try harness.file("b.md")
            let clipboard = ProjectNavigatorClipboard(pasteboard: harness.pasteboard)
            harness.select([first, second])
            #expect(harness.window.makeFirstResponder(harness.outlineView))

            #expect(harness.outlineView.performKeyEquivalent(with: try keyEvent("c", modifiers: .command, in: harness)))
            #expect(clipboard.fileURLs.map(\.lastPathComponent) == ["a.txt", "b.md"])
            #expect(!clipboard.isCut)

            #expect(harness.outlineView.performKeyEquivalent(with: try keyEvent("x", modifiers: .command, in: harness)))
            #expect(clipboard.fileURLs.map(\.lastPathComponent) == ["a.txt", "b.md"])
            #expect(clipboard.isCut)

            harness.select([harness.rootFile])
            harness.pasteboard.removeAllContents()
            #expect(harness.outlineView.performKeyEquivalent(with: try keyEvent("x", modifiers: .command, in: harness)))
            #expect(!clipboard.hasFiles)

            harness.outlineView.deselectAll(nil)
            #expect(harness.outlineView.performKeyEquivalent(with: try keyEvent("c", modifiers: .command, in: harness)))
            #expect(!clipboard.hasFiles)
        }
    }

    @Test
    func otherKeyEquivalentsAreForwardedToTheSuperclass() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            #expect(harness.window.makeFirstResponder(harness.outlineView))
            let plainV = try keyEvent("v", modifiers: [], in: harness)
            let commandShiftV = try keyEvent("V", modifiers: [.command, .shift], in: harness)
            let commandZ = try keyEvent("z", modifiers: .command, in: harness)
            let commandV = try keyEvent("v", modifiers: .command, in: harness)

            #expect(!harness.outlineView.performKeyEquivalent(with: plainV))
            #expect(!harness.outlineView.performKeyEquivalent(with: commandShiftV))
            #expect(!harness.outlineView.performKeyEquivalent(with: commandZ))

            let delegate = harness.outlineView.delegate
            harness.outlineView.delegate = nil
            #expect(!harness.outlineView.performKeyEquivalent(with: commandV))
            harness.outlineView.delegate = delegate
        }
    }

    @Test
    func clipboardMenuItemsAreValidOnlyWhenTheyCanAct() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let copy = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
            let cut = NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "")
            let paste = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "")
            let fromClipboard = try #require(
                harness.menuItem(titled: "New File from Clipboard", in: harness.buildMenu(clicking: harness.rootFile))
            )
            let other = NSMenuItem(
                title: "Other",
                action: #selector(NSResponder.cancelOperation(_:)),
                keyEquivalent: ""
            )
            harness.pasteboard.removeAllContents()

            harness.outlineView.deselectAll(nil)
            #expect(!harness.outlineView.validateMenuItem(copy))
            #expect(!harness.outlineView.validateMenuItem(cut))
            #expect(!harness.outlineView.validateMenuItem(paste))
            #expect(!harness.outlineView.validateMenuItem(fromClipboard))

            harness.select([try harness.file("a.txt")])
            #expect(harness.outlineView.validateMenuItem(copy))
            #expect(harness.outlineView.validateMenuItem(cut))
            #expect(harness.outlineView.validateMenuItem(fromClipboard))
            #expect(!harness.outlineView.validateMenuItem(other))

            harness.pasteboard.replaceContents(withText: "text")
            #expect(harness.outlineView.validateMenuItem(paste))
            harness.writeClipboard(["b.md"], cut: false)
            #expect(harness.outlineView.validateMenuItem(paste))

            let delegate = harness.outlineView.delegate
            harness.outlineView.delegate = nil
            #expect(!harness.outlineView.validateMenuItem(paste))
            harness.outlineView.delegate = delegate
        }
    }

    @Test
    func clipboardActionsWithoutAControllerLeaveTheClipboardAlone() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.select([try harness.file("a.txt")])
            let delegate = harness.outlineView.delegate
            harness.outlineView.delegate = nil

            harness.outlineView.copy(nil)
            harness.outlineView.cut(nil)
            harness.outlineView.paste(nil)
            harness.outlineView.delegate = delegate

            #expect(!ProjectNavigatorClipboard(pasteboard: harness.pasteboard).hasFiles)
            #expect(ProjectNavigatorClipboard(pasteboard: harness.pasteboard).text == nil)
        }
    }
}
