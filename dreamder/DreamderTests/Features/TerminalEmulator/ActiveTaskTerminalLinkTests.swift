import AppKit
import Foundation
import SwiftTerm
import Testing
@testable import Dreamder

@MainActor
final class ConsoleLinkRecorder {
    var targets: [ConsoleFileLinkTarget] = []
}

@MainActor
@Suite(.serialized, .uiGate)
struct ActiveTaskTerminalLinkTests {
    private func makeHarness(
        workspace: URL?,
        workingDirectory: String = "",
        columns: Int? = 400
    ) -> (view: CEActiveTaskTerminalView, recorder: ConsoleLinkRecorder) {
        let task = CETask(name: "Links", workingDirectory: workingDirectory, command: "true")
        let activeTask = CEActiveTask(task: task)
        activeTask.workspaceURL = workspace
        let recorder = ConsoleLinkRecorder()
        activeTask.openFileLink = { recorder.targets.append($0) }
        let view = CEActiveTaskTerminalView(activeTask: activeTask)
        if let columns {
            view.getTerminal().resize(cols: columns, rows: 25)
        }
        return (view, recorder)
    }

    private func touch(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "x".write(to: url, atomically: true, encoding: .utf8)
    }

    private func withWorkspace(_ body: (URL) throws -> Void) throws {
        let directory = try makeTemporaryDirectory(label: "terminal-links")
        defer { removeTemporaryDirectory(directory) }
        try body(directory)
    }

    private func payload(_ view: TerminalView, row: Int, column: Int) -> String? {
        view.getTerminal().getLine(row: row)?[column].getPayload() as? String
    }

    private func payloadColumns(_ view: TerminalView, row: Int) -> [Int] {
        guard let line = view.getTerminal().getLine(row: row) else { return [] }
        return (0..<line.count).filter { line[$0].hasPayload }
    }

    private func rowsWithPayload(_ view: TerminalView) -> [Int] {
        (0..<view.getTerminal().rows).filter { !payloadColumns(view, row: $0).isEmpty }
    }

    private func cellValue(for file: URL, line: Int, column: Int) -> String {
        ConsoleFileLinkPayload(
            path: file.standardizedFileURL.path(percentEncoded: false),
            line: line,
            column: column
        ).cellValue
    }

    @Test
    func theForwarderOwnsTheTerminalDelegateSlot() {
        let (view, _) = makeHarness(workspace: nil, columns: nil)

        #expect(view.terminalDelegate is ActiveTaskTerminalLinkForwarder)
    }

    @Test
    func existingAbsoluteFilesGetPayloadsExactlyOnTheLinkText() throws {
        try withWorkspace { directory in
            let file = directory.appending(path: "File.swift")
            try touch(file)
            let path = file.path(percentEncoded: false)
            let (view, _) = makeHarness(workspace: directory)

            view.feed(text: "\(path):12:5: error: boom\r\n")

            let length = "\(path):12:5".count
            let expected = cellValue(for: file, line: 12, column: 5)
            #expect(payloadColumns(view, row: 0) == Array(0..<length))
            #expect(rowsWithPayload(view) == [0])
            for column in 0..<length {
                #expect(payload(view, row: 0, column: column) == expected)
            }
            #expect(payload(view, row: 0, column: length) == nil)
        }
    }

    @Test
    func relativeLinksResolveAgainstTheWorkspace() throws {
        try withWorkspace { directory in
            let file = directory.appending(path: "File.swift")
            try touch(file)
            let (view, _) = makeHarness(workspace: directory)

            view.feed(text: "File.swift:12:5: error: boom\r\n")

            #expect(payloadColumns(view, row: 0) == Array(0..<"File.swift:12:5".count))
            #expect(payload(view, row: 0, column: 0) == cellValue(for: file, line: 12, column: 5))
        }
    }

    @Test
    func coloredOutputStillMapsColumnsToCells() throws {
        try withWorkspace { directory in
            let file = directory.appending(path: "File.swift")
            try touch(file)
            let (view, _) = makeHarness(workspace: directory)

            view.feed(text: "\u{1b}[1;31merror\u{1b}[0m: \u{1b}[36mFile.swift:3:7\u{1b}[0m: boom\r\n")

            #expect(payloadColumns(view, row: 0) == Array(7..<21))
            #expect(payload(view, row: 0, column: 7) == cellValue(for: file, line: 3, column: 7))
        }
    }

    @Test
    func linksToMissingFilesGetNoPayload() throws {
        try withWorkspace { directory in
            let (view, _) = makeHarness(workspace: directory)

            view.feed(text: "Missing.swift:1:1: error: boom\r\n\(directory.path(percentEncoded: false))/Gone.swift:2\r\n")

            #expect(rowsWithPayload(view).isEmpty)
        }
    }

    @Test
    func linesWithoutWorkspaceOnlyLinkAbsoluteFiles() throws {
        try withWorkspace { directory in
            let file = directory.appending(path: "File.swift")
            try touch(file)
            let (view, _) = makeHarness(workspace: nil)

            view.feed(text: "File.swift:1\r\n\(file.path(percentEncoded: false)):2\r\n")

            #expect(rowsWithPayload(view) == [1])
        }
    }

    @Test
    func everyLinkOfALineGetsItsOwnPayload() throws {
        try withWorkspace { directory in
            let first = directory.appending(path: "A.swift")
            let second = directory.appending(path: "B.swift")
            try touch(first)
            try touch(second)
            let (view, _) = makeHarness(workspace: directory)

            view.feed(text: "A.swift:1:2 then B.swift:3 and Missing.swift:4\r\n")

            let firstLength = "A.swift:1:2".count
            let secondStart = "A.swift:1:2 then ".count
            let secondLength = "B.swift:3".count
            #expect(payloadColumns(view, row: 0) == Array(0..<firstLength) + Array(secondStart..<(secondStart + secondLength)))
            #expect(payload(view, row: 0, column: 0) == cellValue(for: first, line: 1, column: 2))
            #expect(payload(view, row: 0, column: secondStart) == cellValue(for: second, line: 3, column: 1))
        }
    }

    @Test
    func wideCharactersBeforeALinkKeepTheColumnsAligned() throws {
        try withWorkspace { directory in
            try touch(directory.appending(path: "File.swift"))
            let (view, _) = makeHarness(workspace: directory)

            view.feed(text: "日本 File.swift:4\r\n")

            #expect(payloadColumns(view, row: 0) == Array(5..<17))
        }
    }

    @Test
    func aLinkThatEndsAtTheLastColumnOfTheRowIsMarkedUpToTheRowEnd() throws {
        try withWorkspace { directory in
            try touch(directory.appending(path: "File.swift"))
            let (view, _) = makeHarness(workspace: directory, columns: 20)

            view.feed(text: "        File.swift:3\r\n")

            #expect(payloadColumns(view, row: 0) == Array(8..<20))
        }
    }

    @Test
    func linksOnLinesThatScrolledTheViewportAreMarked() throws {
        try withWorkspace { directory in
            try touch(directory.appending(path: "File.swift"))
            let (view, _) = makeHarness(workspace: directory)
            let rows = view.getTerminal().rows

            for index in 0..<(rows + 10) {
                view.feed(text: "noise \(index)\r\n")
            }
            view.feed(text: "File.swift:3:9: error\r\n")

            #expect(rowsWithPayload(view) == [rows - 2])
            #expect(payloadColumns(view, row: rows - 2) == Array(0..<"File.swift:3:9".count))
        }
    }

    @Test
    func linesCompletedBelowAScrollRegionAreMarkedOnTheCursorRow() throws {
        try withWorkspace { directory in
            try touch(directory.appending(path: "File.swift"))
            let (view, _) = makeHarness(workspace: directory)
            let lastRow = view.getTerminal().rows - 1

            view.feed(text: "\u{1b}[1;3r\u{1b}[\(lastRow + 1);1HFile.swift:2\r\n")

            #expect(rowsWithPayload(view) == [lastRow])
            #expect(payloadColumns(view, row: lastRow) == Array(0..<"File.swift:2".count))
        }
    }

    @Test
    func aSingleRowTerminalNeverMarksOrCrashes() throws {
        try withWorkspace { directory in
            try touch(directory.appending(path: "File.swift"))
            let (view, _) = makeHarness(workspace: directory)
            view.getTerminal().resize(cols: 80, rows: 1)

            view.feed(text: "File.swift:2\r\nFile.swift:3\r\n")

            #expect(rowsWithPayload(view).isEmpty)
        }
    }

    @Test
    func wrappedLinesAreMarkedOnTheirLastPhysicalRowOnly() throws {
        try withWorkspace { directory in
            try touch(directory.appending(path: "File.swift"))
            let (view, _) = makeHarness(workspace: directory)
            view.getTerminal().resize(cols: 80, rows: 25)

            view.feed(text: String(repeating: "x", count: 90) + " File.swift:3\r\n")
            view.feed(text: String(repeating: "x", count: 74) + " File.swift:3\r\n")

            #expect(rowsWithPayload(view) == [1])
            #expect(payloadColumns(view, row: 1) == Array(11..<23))
        }
    }

    @Test
    func anExhaustedAtomTableLeavesTheLineUnmarked() throws {
        try withWorkspace { directory in
            try touch(directory.appending(path: "File.swift"))
            let (view, _) = makeHarness(workspace: directory)
            view.makeLinkAtom = { _ in nil }

            view.feed(text: "File.swift:3\r\n")

            #expect(rowsWithPayload(view).isEmpty)
        }
    }

    @Test
    func workingDirectoryComesBeforeTheWorkspaceRoot() throws {
        try withWorkspace { directory in
            let nested = directory.appending(path: "pkg/Make.swift")
            let rootFile = directory.appending(path: "top.swift")
            try touch(nested)
            try touch(rootFile)
            let (view, _) = makeHarness(workspace: directory, workingDirectory: "pkg")

            view.feed(text: "Make.swift:3:1\r\ntop.swift:2\r\n")

            #expect(payload(view, row: 0, column: 0) == cellValue(for: nested, line: 3, column: 1))
            #expect(payload(view, row: 1, column: 0) == cellValue(for: rootFile, line: 2, column: 1))
        }
    }

    @Test
    func openLinkRequestsResolveAgainstTheWorkingDirectoryThenTheWorkspace() throws {
        try withWorkspace { directory in
            let nested = directory.appending(path: "pkg/Make.swift")
            let rootFile = directory.appending(path: "top.swift")
            try touch(nested)
            try touch(rootFile)
            let (view, recorder) = makeHarness(workspace: directory, workingDirectory: "pkg", columns: nil)
            let forwarder = try #require(view.terminalDelegate)

            forwarder.requestOpenLink(source: view, link: "Make.swift", params: ["line": "3", "column": "4"])
            forwarder.requestOpenLink(source: view, link: "top.swift", params: ["line": "7", "column": "1"])

            #expect(recorder.targets.map(\.line) == [3, 7])
            #expect(recorder.targets.map(\.column) == [4, 1])
            #expect(recorder.targets.map { $0.url.standardizedFileURL } == [
                nested.standardizedFileURL,
                rootFile.standardizedFileURL
            ])
        }
    }

    @Test
    func openLinkRequestsRoundTripTheMarkedPayload() throws {
        try withWorkspace { directory in
            let file = directory.appending(path: "dir with ;:% chars/File.swift")
            try touch(file)
            let (view, recorder) = makeHarness(workspace: directory)
            let forwarder = try #require(view.terminalDelegate)
            let cell = ConsoleFileLinkPayload(
                path: file.standardizedFileURL.path(percentEncoded: false),
                line: 21,
                column: 8
            ).cellValue
            let parts = cell.split(separator: ";", maxSplits: Int.max, omittingEmptySubsequences: false)

            forwarder.requestOpenLink(
                source: view,
                link: String(parts[1]),
                params: ["line": "21", "column": "8"]
            )

            #expect(recorder.targets.count == 1)
            #expect(
                recorder.targets.first?.url.resolvingSymlinksInPath().path(percentEncoded: false)
                    == file.resolvingSymlinksInPath().path(percentEncoded: false)
            )
            #expect(recorder.targets.first?.line == 21)
            #expect(recorder.targets.first?.column == 8)
        }
    }

    @Test
    func unresolvedOrMalformedLinkRequestsDoNothing() throws {
        try withWorkspace { directory in
            let file = directory.appending(path: "a.swift")
            try touch(file)
            let (view, recorder) = makeHarness(workspace: nil, columns: nil)
            let forwarder = try #require(view.terminalDelegate)
            let params = ["line": "1", "column": "1"]

            forwarder.requestOpenLink(source: view, link: "missing.swift", params: params)
            forwarder.requestOpenLink(source: view, link: "a.swift", params: params)
            forwarder.requestOpenLink(source: view, link: file.path(percentEncoded: false), params: [:])
            forwarder.requestOpenLink(source: view, link: "%zz", params: params)
            forwarder.requestOpenLink(source: view, link: directory.path(percentEncoded: false), params: params)
            view.activeTask.openFileLink = nil
            forwarder.requestOpenLink(source: view, link: file.path(percentEncoded: false), params: params)

            #expect(recorder.targets.isEmpty)
        }
    }

    @Test
    func theForwarderPassesEveryOtherDelegateCallToTheView() throws {
        let (view, _) = makeHarness(workspace: nil, columns: nil)
        let delegate = TerminalCoverageDelegate()
        view.processDelegate = delegate
        let pasteboard = RecordingTerminalPasteboard()
        view.pasteboard = pasteboard.writer
        let forwarder = try #require(view.terminalDelegate)

        forwarder.setTerminalTitle(source: view, title: "build output")
        forwarder.hostCurrentDirectoryUpdate(source: view, directory: "file:///tmp/project")
        forwarder.hostCurrentDirectoryUpdate(source: view, directory: nil)
        forwarder.clipboardCopy(source: view, content: Data("from-osc-52".utf8))
        forwarder.sizeChanged(source: view, newCols: 90, newRows: 30)
        forwarder.scrolled(source: view, position: 0.5)
        forwarder.rangeChanged(source: view, startY: 0, endY: 1)
        forwarder.send(source: view, data: Array("ignored".utf8)[...])

        #expect(delegate.titles == ["build output"])
        #expect(delegate.directories == ["file:///tmp/project", nil])
        #expect(pasteboard.writes == ["from-osc-52"])
        #expect(delegate.sizes.isEmpty)
        #expect(!view.process.running)
    }

    @Test
    func aCommandClickOnALinkOpensTheFile() throws {
        try withWorkspace { directory in
            let file = directory.appending(path: "File.swift")
            try touch(file)
            let (view, recorder) = makeHarness(workspace: directory, columns: nil)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: view.frame.size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: true
            )
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.feed(text: "File.swift:12:5: error: boom\r\n")
            let firstCell = NSPoint(x: 1, y: view.frame.height - 1)
            let lastCell = NSPoint(x: view.frame.width - 1, y: view.frame.height - 1)

            @MainActor func click(at point: NSPoint, modifiers: NSEvent.ModifierFlags) throws {
                let event = try #require(
                    NSEvent.mouseEvent(
                        with: .leftMouseUp,
                        location: point,
                        modifierFlags: modifiers,
                        timestamp: 0,
                        windowNumber: window.windowNumber,
                        context: nil,
                        eventNumber: 0,
                        clickCount: 1,
                        pressure: 0
                    )
                )
                view.mouseUp(with: event)
            }

            try click(at: firstCell, modifiers: [])
            try click(at: lastCell, modifiers: [.command])
            #expect(recorder.targets.isEmpty)

            try click(at: firstCell, modifiers: [.command])

            #expect(recorder.targets.count == 1)
            #expect(recorder.targets.first?.url.standardizedFileURL == file.standardizedFileURL)
            #expect(recorder.targets.first?.line == 12)
            #expect(recorder.targets.first?.column == 5)
            window.contentView = nil
        }
    }
}
