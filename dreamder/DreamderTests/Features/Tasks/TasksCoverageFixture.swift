import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
final class TasksCoverageFixture {
    static let markersDirectoryVariable = "TASKS_COVERAGE_MARKERS"
    static let readyFile = "ready"
    static let terminateFile = "terminate"
    static let interruptFile = "interrupt"
    static let unhandledSignalExitCode: Int32 = 7

    static let signalLoopCommand = """
    trap 'm=got-term-$((20+2)); echo $m >> "$\(markersDirectoryVariable)/\(terminateFile)"; echo $m; exit 0' TERM; \
    trap 'm=got-int-$((30+3)); echo $m >> "$\(markersDirectoryVariable)/\(interruptFile)"; echo $m; exit 0' INT; \
    m=ready-$((40+2)); echo $m >> "$\(markersDirectoryVariable)/\(readyFile)"; echo $m; \
    i=0; while [ $i -lt 600 ]; do sleep 0.1; i=$((i+1)); done; exit \(unhandledSignalExitCode)
    """

    static let readyMarker = "ready-42"
    static let terminateMarker = "got-term-22"
    static let interruptMarker = "got-int-33"

    let zdotdir: URL
    let homeDirectory: URL
    let markersDirectory: URL
    let settingsStore: Dreamder.Settings

    init() throws {
        zdotdir = try makeTemporaryDirectory(label: "tasks-coverage-zdotdir")
        homeDirectory = try makeTemporaryDirectory(label: "tasks-coverage-home")
        markersDirectory = try makeTemporaryDirectory(label: "tasks-coverage-markers")
        for name in [".zshenv", ".zprofile", ".zshrc", ".zlogin"] {
            try "".write(to: zdotdir.appending(path: name), atomically: true, encoding: .utf8)
        }
        settingsStore = Dreamder.Settings(baseURL: zdotdir.appending(path: "settings", directoryHint: .isDirectory))
        settingsStore.preferences.terminal.shell = .zsh
    }

    deinit {
        try? FileManager.default.removeItem(at: zdotdir)
        try? FileManager.default.removeItem(at: homeDirectory)
        try? FileManager.default.removeItem(at: markersDirectory)
    }

    var zdotdirPath: String {
        zdotdir.path(percentEncoded: false)
    }

    func makeTask(name: String = "Coverage Task", command: String) -> CETask {
        CETask(
            name: name,
            command: command,
            environmentVariables: [
                CETask.EnvironmentVariable(key: "ZDOTDIR", value: zdotdirPath),
                CETask.EnvironmentVariable(key: "HOME", value: homeDirectory.path(percentEncoded: false)),
                CETask.EnvironmentVariable(
                    key: Self.markersDirectoryVariable,
                    value: markersDirectory.path(percentEncoded: false)
                )
            ]
        )
    }

    func makeSignalTask(name: String = "Signal Task") -> CETask {
        makeTask(name: name, command: Self.signalLoopCommand)
    }

    func waitUntilReady(
        _ output: CEActiveTaskTerminalView,
        occurrences: Int = 1,
        timeout: Duration = .seconds(90)
    ) async throws {
        try await eventually(timeout: timeout) {
            output.getBufferAsString().components(separatedBy: Self.readyMarker).count - 1 >= occurrences
        }
    }

    func waitForOutput(
        _ output: CEActiveTaskTerminalView,
        containing marker: String,
        timeout: Duration = .seconds(90)
    ) async throws {
        try await eventually(timeout: timeout) {
            output.getBufferAsString().contains(marker)
        }
    }

    func waitUntilSignalTaskIsReady(timeout: Duration) async throws {
        try await waitForMarker(Self.readyMarker, in: Self.readyFile, timeout: timeout)
    }

    func waitForMarker(_ marker: String, in fileName: String, timeout: Duration) async throws {
        try await eventually(timeout: timeout) {
            markerFileContents(fileName).contains(marker)
        }
    }

    func markerFileContents(_ fileName: String) -> String {
        let url = markersDirectory.appending(path: fileName)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}

@MainActor
final class TasksCoverageNotificationRecorder {
    struct Entry: Sendable {
        let id: String?
        let action: String?
        let title: String?
    }

    private(set) var entries: [Entry] = []
    private var token: (any NSObjectProtocol)?

    init() {
        token = NotificationCenter.default.addObserver(
            forName: .taskNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let info = notification.userInfo
            let entry = Entry(
                id: info?["id"] as? String,
                action: info?["action"] as? String,
                title: info?["title"] as? String
            )
            MainActor.assumeIsolated {
                self?.entries.append(entry)
            }
        }
    }

    func stop() {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
        token = nil
    }

    func entries(for id: String) -> [Entry] {
        entries.filter { $0.id == id }
    }
}

nonisolated enum TasksCoverageProcessProbe {
    private static let stoppedStatus: UInt32 = 4
    static let backgroundChildCommand = "sleep 600 & echo child-pid-$!-end; wait"
    static let childPIDPrefix = "child-pid-"
    static let childPIDSuffix = "-end"

    static func isStopped(_ pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let written = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        return written == size && info.pbi_status == stoppedStatus
    }

    static func isGone(_ pid: pid_t) -> Bool {
        kill(pid, 0) != 0
    }

    static func announcedPID(in text: String) -> pid_t? {
        guard let start = text.range(of: childPIDPrefix, options: .backwards) else { return nil }
        let rest = text[start.upperBound...]
        guard let end = rest.range(of: childPIDSuffix) else { return nil }
        return pid_t(rest[..<end.lowerBound])
    }
}

@MainActor
func withCoverageSettingsStore<Result>(
    perform body: (Dreamder.Settings) async throws -> Result
) async rethrows -> Result {
    if let current = SettingsScope.current {
        return try await body(current)
    }
    let directory = (try? makeTemporaryDirectory(label: "CoverageSettings"))
        ?? URL.temporaryDirectory.appending(path: "CoverageSettings-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { removeTemporaryDirectory(directory) }
    let store = Dreamder.Settings(baseURL: directory)
    return try await SettingsScope.$current.withValue(store) {
        try await body(store)
    }
}

@MainActor
func withTerminalCoverageSettings(
    _ configure: (inout SettingsData.TerminalSettings) -> Void,
    perform body: () async throws -> Void
) async rethrows {
    try await withCoverageSettingsStore { store in
        configure(&store.preferences.terminal)
        try await body()
    }
}

@MainActor
func withTerminalCoverageSettings(
    shellIntegration: Bool,
    perform body: () async throws -> Void
) async rethrows {
    try await withTerminalCoverageSettings({ $0.useShellIntegration = shellIntegration }, perform: body)
}

func makeEmptyShellIntegrationBundle(in directory: URL) throws -> Bundle {
    try #require(Bundle(path: directory.path(percentEncoded: false)))
}
