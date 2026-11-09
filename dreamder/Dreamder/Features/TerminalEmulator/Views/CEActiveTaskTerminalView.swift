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
        adoptPseudoTerminal()
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        lastOutputAt = .now
        super.dataReceived(slice: slice)
    }

    override func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        let status = exitCode ?? 1
        lastOutputAt = .now
        Task { @MainActor [weak self] in
            while let self, self.process.childfd != -1, ContinuousClock.now - self.lastOutputAt < Self.drainIdleLimit {
                try? await Task.sleep(for: Self.drainInterval)
            }
            self?.drainProcessEvents()
            self?.activeTask.handleProcessFinished(terminationStatus: status)
        }
    }

    private var lastOutputAt = ContinuousClock.now
    private static let drainInterval: Duration = .milliseconds(10)
    private static let drainIdleLimit: Duration = .seconds(5)

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
        if process.shellPid != 0 {
            return process.shellPid
        }
        return nil
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
