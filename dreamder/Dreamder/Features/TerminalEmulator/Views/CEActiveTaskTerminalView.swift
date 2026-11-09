//
//  CEActiveTaskTerminalView.swift
//  Dreamder
//
//  Created by Khan Winter on 7/14/25.
//

import AppKit
import SwiftTerm

class CEActiveTaskTerminalView: CELocalShellTerminalView {
    var activeTask: CEActiveTask
    var makeLinkAtom: (String) -> TinyAtom? = { TinyAtom.lookup(value: $0) }
    var shellIntegrationDirectory = FileManager.default.temporaryDirectory

    private let linkDetector = ConsoleFileLinkDetector()
    private var linkForwarder: ActiveTaskTerminalLinkForwarder?

    static let detachedFrame = NSRect(x: 0, y: 0, width: 960, height: 480)

    init(activeTask: CEActiveTask) {
        self.activeTask = activeTask
        super.init(frame: Self.detachedFrame)
        settings = activeTask.settings
        let forwarder = ActiveTaskTerminalLinkForwarder(view: self)
        linkForwarder = forwarder
        terminalDelegate = forwarder
    }

    public required init?(coder: NSCoder) {
        nil
    }

    override func startProcess(
        workspaceURL url: URL?,
        shell: Shell? = nil,
        environment: [String] = [],
        interactive: Bool = true
    ) {
        let terminalSettings = settings.preferences.terminal

        var terminalEnvironment: [String] = Terminal.getEnvironmentVariables()
        terminalEnvironment.append("TERM_PROGRAM=DreamderApp_Terminal")

        guard let (shell, shellPath) = getShell(shell, userSetting: terminalSettings.shell) else {
            return
        }

        terminalEnvironment.append(contentsOf: environment)
        terminalEnvironment.append("\(ShellIntegration.Variables.disableHistory)=1")
        terminalEnvironment.append(
            contentsOf: activeTask.task.environmentVariables.map({ $0.key + "=" + $0.value })
        )

        var shellArgs = ["-lic"]
        if terminalSettings.useShellIntegration,
           let integrationArgs = try? ShellIntegration.setUpIntegration(
                for: shell,
                environment: &terminalEnvironment,
                useLogin: true,
                interactive: interactive,
                bundle: shellIntegrationBundle,
                temporaryDirectory: shellIntegrationDirectory
           ) {
            shellArgs = integrationArgs + ["-c"]
        }
        shellArgs.append(activeTask.task.command)

        sendOutputMessage("Starting task: " + self.activeTask.task.name)
        sendOutputMessage(self.activeTask.task.command)
        newline()

        process.startProcess(
            executable: shellPath,
            args: shellArgs,
            environment: terminalEnvironment,
            execName: shell.rawValue,
            currentDirectory: URL(filePath: activeTask.task.workingDirectory, relativeTo: url).absolutePath
        )
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        receivedByteCount += slice.count
        super.dataReceived(slice: slice)
    }

    override func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        let status = exitCode ?? 1
        Task { @MainActor [weak self] in
            await self?.drainUntilEndOfOutput()
            self?.drainProcessEvents()
            self?.activeTask.handleProcessFinished(terminationStatus: status)
        }
    }

    var drainPollInterval: Duration = .milliseconds(10)
    var drainStallRounds = 500
    private var receivedByteCount = 0

    private func drainUntilEndOfOutput() async {
        await Self.waitForEndOfOutput(
            isOpen: { self.process.childfd != -1 },
            receivedBytes: { self.receivedByteCount },
            interval: drainPollInterval,
            stallRounds: drainStallRounds
        )
    }

    static func waitForEndOfOutput(
        isOpen: () -> Bool,
        receivedBytes: () -> Int,
        interval: Duration,
        stallRounds: Int,
        sleep: (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) async {
        var stalledRounds = 0
        var received = receivedBytes()
        while isOpen(), stalledRounds < stallRounds {
            await sleep(interval)
            let current = receivedBytes()
            stalledRounds = current == received ? stalledRounds + 1 : 0
            received = current
        }
    }

    func sendOutputMessage(_ message: String) {
        sendSpecialSequence()
        feed(text: message)
        newline()
    }

    func sendSpecialSequence() {
        let start: [UInt8] = [0x1B, 0x5B, 0x37, 0x6D]
        let end: [UInt8] = [0x1B, 0x5B, 0x30, 0x6D]
        feed(byteArray: start[0..<start.count])
        feed(text: " * ")
        feed(byteArray: end[0..<end.count])
        feed(text: " ")
    }

    func newline() {
        // cr cr lf
        feed(byteArray: [13, 13, 10])
    }

    func runningPID() -> pid_t? {
        process.running && process.shellPid > 0 ? process.shellPid : nil
    }

    func getBufferAsString() -> String {
        String(decoding: terminal.getBufferAsData(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    override func linefeed(source: Terminal) {
        super.linefeed(source: source)
        let cursorRow = source.buffer.y
        markFileLinks(inRow: cursorRow - 1)
        if cursorRow == source.rows - 1 {
            markFileLinks(inRow: cursorRow)
        }
    }

    func openConsoleLink(link: String, params: [String: String]) {
        guard let payload = ConsoleFileLinkPayload(link: link, params: params),
              let target = linkResolver.target(path: payload.path, line: payload.line, column: payload.column)
        else { return }
        activeTask.openFileLink?(target)
    }

    private var linkResolver: ConsoleFileLinkResolver {
        let workspaceURL = activeTask.workspaceURL
        let baseDirectories = workspaceURL.map {
            [URL(filePath: activeTask.task.workingDirectory, relativeTo: $0), $0]
        } ?? []
        return ConsoleFileLinkResolver(baseDirectories: baseDirectories)
    }

    private func markFileLinks(inRow row: Int) {
        guard let line = terminal.getLine(row: row) else { return }
        var characters: [Character] = []
        var columns: [Int] = []
        for column in 0..<line.count {
            let cell = line[column]
            guard cell.width > 0 else { continue }
            let character = cell.getCharacter()
            characters.append(character == "\0" ? " " : character)
            columns.append(column)
        }
        let links = linkDetector.links(inCharacters: characters)
        guard !links.isEmpty else { return }
        let resolver = linkResolver
        for link in links {
            guard let target = resolver.target(for: link),
                  let atom = makeLinkAtom(ConsoleFileLinkPayload(target: target).cellValue)
            else { continue }
            let endColumn = (link.range.upperBound < columns.count ? columns[link.range.upperBound] : line.count) - 1
            for column in columns[link.range.lowerBound]...endColumn {
                var cell = line[column]
                cell.setPayload(atom: atom)
                line[column] = cell
            }
        }
    }
}
