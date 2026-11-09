import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct ActiveTaskTerminalWideCharacterTests {
    private func makeView(workspace: URL) -> (view: CEActiveTaskTerminalView, recorder: ConsoleLinkRecorder) {
        let activeTask = CEActiveTask(task: CETask(name: "Links", command: "true"))
        activeTask.workspaceURL = workspace
        let recorder = ConsoleLinkRecorder()
        activeTask.openFileLink = { recorder.targets.append($0) }
        let view = CEActiveTaskTerminalView(activeTask: activeTask)
        view.getTerminal().resize(cols: 200, rows: 25)
        return (view, recorder)
    }

    @Test
    func linksAfterZeroWidthCharactersAreDetectedAtTheirCells() throws {
        let directory = try makeTemporaryDirectory(label: "terminal-wide-links")
        defer { removeTemporaryDirectory(directory) }
        let file = directory.appending(path: "src/a.swift")
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let (view, _) = makeView(workspace: directory)

        view.feed(text: "a\u{200B}b src/a.swift:3\r\n")

        let line = try #require(view.getTerminal().getLine(row: 0))
        let linkedColumns = (0..<line.count).filter { line[$0].hasPayload }
        let linkLength = "src/a.swift:3".count
        let firstLinkColumn = 4
        #expect(line[0].width == 1)
        #expect(line[1].width == 0)
        #expect(linkedColumns == Array(firstLinkColumn..<(firstLinkColumn + linkLength)))
        let expected = ConsoleFileLinkPayload(
            path: file.standardizedFileURL.path(percentEncoded: false),
            line: 3,
            column: 1
        ).cellValue
        #expect(line[firstLinkColumn].getPayload() as? String == expected)
    }
}
