import AppKit
import Foundation
import SwiftTerm
import Testing
@testable import Dreamder

@MainActor
final class TerminalCoverageDelegate: CELocalShellTerminalViewDelegate {
    var sizes: [[Int]] = []
    var titles: [String] = []
    var directories: [String?] = []
    var exits: [ProcessExit?] = []

    func sizeChanged(source: CETerminalView, newCols: Int, newRows: Int) {
        sizes.append([newCols, newRows])
    }

    func setTerminalTitle(source: CETerminalView, title: String) {
        titles.append(title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        directories.append(directory)
    }

    func processTerminated(source: TerminalView, exit: ProcessExit?) {
        exits.append(exit)
    }
}

@MainActor
func terminalCoverageText(_ view: TerminalView) -> String {
    String(decoding: view.getTerminal().getBufferAsData(), as: UTF8.self)
}

@MainActor
func terminalCoverageView(width: CGFloat = 640, height: CGFloat = 320) -> CELocalShellTerminalView {
    CELocalShellTerminalView(frame: NSRect(x: 0, y: 0, width: width, height: height))
}

@MainActor
final class RecordingTerminalPasteboard {
    private(set) var writes: [String] = []

    var writer: TerminalPasteboardWriter {
        TerminalPasteboardWriter { [self] text in writes.append(text) }
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct TerminalViewCoverageTests {
    @Test
    func zeroSizedFramesNeverReachTheTerminal() {
        let view = terminalCoverageView(width: 640, height: 320)

        view.setFrameSize(.zero)
        #expect(view.frame.size == NSSize(width: 640, height: 320))

        view.frame = .zero
        #expect(view.frame.size == NSSize(width: 640, height: 320))

        view.setFrameSize(NSSize(width: 500, height: 250))
        #expect(view.frame.size == NSSize(width: 500, height: 250))

        view.frame = NSRect(x: 0, y: 0, width: 420, height: 210)
        #expect(view.frame.size == NSSize(width: 420, height: 210))
    }

    @Test
    func copyWritesTheSelectionToTheInjectedPasteboard() {
        let pasteboard = RecordingTerminalPasteboard()
        let view = terminalCoverageView()
        view.pasteboard = pasteboard.writer
        view.feed(text: "copy-me-please")

        view.selectAll(nil)
        view.copy(view)

        #expect(pasteboard.writes.count == 1)
        #expect(pasteboard.writes.first?.contains("copy-me-please") == true)
    }

    @Test
    func writerReplacesThePasteboardTextOfTheGivenPasteboard() {
        let pasteboard = InMemoryPasteboard()

        TerminalPasteboardWriter.writing(to: pasteboard).write("terminal text")

        #expect(pasteboard.plainText == "terminal text")
        #expect(pasteboard.textWrites == ["terminal text"])
    }

    @Test
    func clipboardCopyWritesTextAndIgnoresInvalidUtf8() {
        let pasteboard = RecordingTerminalPasteboard()
        let view = terminalCoverageView()
        view.pasteboard = pasteboard.writer

        view.clipboardCopy(source: view, content: Data("from-osc-52".utf8))
        #expect(pasteboard.writes == ["from-osc-52"])

        view.clipboardCopy(source: view, content: Data([0xFF, 0xFE, 0xFD]))
        #expect(pasteboard.writes == ["from-osc-52"])
    }

    @Test
    func accessibilityDescribesTheTerminalContent() {
        let view = terminalCoverageView()
        view.feed(text: "accessible-output")

        #expect(view.isAccessibilityElement())
        #expect(view.isAccessibilityEnabled())
        #expect(view.accessibilityLabel() == "Terminal Emulator")
        #expect(view.accessibilityRole() == .textArea)
        let value = view.accessibilityValue() as? String
        #expect(value?.contains("accessible-output") == true)

        view.selectAll(nil)
        #expect(view.accessibilitySelectedText()?.contains("accessible-output") == true)
    }

    @Test
    func terminalDelegateCallbacksReachTheProcessDelegate() {
        let view = terminalCoverageView()
        let delegate = TerminalCoverageDelegate()
        view.processDelegate = delegate

        view.setTerminalTitle(source: view, title: "build output")
        view.hostCurrentDirectoryUpdate(source: view, directory: "file:///tmp/project")
        view.hostCurrentDirectoryUpdate(source: view, directory: nil)
        view.processTerminated(view.process, exitCode: 4 << 8)
        view.processTerminated(view.process, exitCode: 9)
        view.processTerminated(view.process, exitCode: nil)

        #expect(delegate.titles == ["build output"])
        #expect(delegate.directories == ["file:///tmp/project", nil])
        #expect(delegate.exits == [.exited(code: 4), .signaled(signal: 9), nil])
    }

    @Test
    func dataReceivedFromTheShellIsFedIntoTheTerminal() {
        let view = terminalCoverageView()

        view.dataReceived(slice: Array("from-the-shell".utf8)[...])

        #expect(terminalCoverageText(view).contains("from-the-shell"))
    }

    @Test
    func inertCallbacksAndASilentProcessChangeNothing() {
        let view = terminalCoverageView()
        let delegate = TerminalCoverageDelegate()
        view.processDelegate = delegate

        view.rangeChanged(source: view, startY: 0, endY: 1)
        view.scrolled(source: view, position: 0.5)
        view.send(source: view, data: Array("ignored".utf8)[...])
        view.sizeChanged(source: view, newCols: 90, newRows: 30)

        #expect(delegate.sizes.isEmpty)
        #expect(!view.process.running)
    }

    @Test
    func decodingFromACoderBuildsATerminalView() throws {
        let archive = try NSKeyedArchiver.archivedData(
            withRootObject: NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100)),
            requiringSecureCoding: false
        )
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archive)
        unarchiver.requiresSecureCoding = false
        unarchiver.setClass(CELocalShellTerminalView.self, forClassName: "NSView")

        let decoded = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? CELocalShellTerminalView
        unarchiver.finishDecoding()

        let view = try #require(decoded)
        #expect(view.terminal != nil)
        #expect(view.processDelegate == nil)
    }

    @Test
    func taskTerminalCannotBeDecodedFromACoder() throws {
        let archive = try NSKeyedArchiver.archivedData(
            withRootObject: NSView(frame: .zero),
            requiringSecureCoding: false
        )
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archive)
        unarchiver.requiresSecureCoding = false

        #expect(CEActiveTaskTerminalView(coder: unarchiver) == nil)
        unarchiver.finishDecoding()
    }

    @Test(arguments: [Shell.zsh, Shell.bash])
    func startingWithoutTheIntegrationScriptsReportsTheFailureInTheTerminal(_ shell: Shell) async throws {
        try await withTempDir { directory in
            try await withTerminalCoverageSettings({ $0.useShellIntegration = true }) {
                let view = terminalCoverageView()
                let delegate = TerminalCoverageDelegate()
                view.processDelegate = delegate
                view.shellIntegrationBundle = try makeEmptyShellIntegrationBundle(in: directory)

                view.startProcess(workspaceURL: directory, shell: shell)

                #expect(delegate.titles == [shell.rawValue])
                #expect(!view.process.running)
                #expect(
                    terminalCoverageText(view).contains(
                        "Failed to start a terminal session: Failed to find \(shell.rawValue) injection file."
                    )
                )
            }
        }
    }

    @Test
    func startProcessRunsAnInteractiveShellInTheRequestedFolder() async throws {
        let fixture = try TasksCoverageFixture()
        try await withTempDir { directory in
            let folder = directory.appending(path: "cwd-check", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try await withTerminalCoverageSettings({ $0.useShellIntegration = false }) {
                let view = terminalCoverageView()
                let delegate = TerminalCoverageDelegate()
                view.processDelegate = delegate
                defer {
                    if view.process.running, view.process.shellPid != 0 {
                        kill(view.process.shellPid, SIGKILL)
                    }
                }

                view.startProcess(
                    workspaceURL: folder,
                    shell: .zsh,
                    environment: ["ZDOTDIR=\(fixture.zdotdirPath)"]
                )

                #expect(delegate.titles == ["zsh"])
                #expect(view.process.running)
                try await eventually {
                    !terminalCoverageText(view).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }

                view.sizeChanged(source: view, newCols: 100, newRows: 30)
                #expect(delegate.sizes.last == [100, 30])

                view.send(source: view, data: Array("echo cwd-${PWD##*/}-$((20+1))\n".utf8)[...])
                try await eventually { terminalCoverageText(view).contains("cwd-cwd-check-21") }

                view.send(source: view, data: Array("exit 3\n".utf8)[...])
                try await eventually(timeout: .seconds(20)) { !delegate.exits.isEmpty }
                #expect(delegate.exits == [.exited(code: 3)])
                try await eventually(timeout: .seconds(20)) { !view.process.running }
            }
        }
    }

    @Test
    func startProcessWithTheBundledIntegrationScriptsRunsTheShellThroughThem() async throws {
        try await withTempDir { directory in
            try await withTerminalCoverageSettings(shellIntegration: true) {
                let view = terminalCoverageView()
                let delegate = TerminalCoverageDelegate()
                view.processDelegate = delegate
                defer { view.terminateSession() }

                view.startProcess(workspaceURL: directory, shell: .bash)

                #expect(delegate.titles == ["bash"])
                #expect(view.process.running)
                view.send(source: view, data: Array("echo integration-$((20+1))\n".utf8)[...])
                try await eventually { terminalCoverageText(view).contains("integration-21") }
                #expect(!terminalCoverageText(view).contains("Failed to start a terminal session"))
            }
        }
    }
}
