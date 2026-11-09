import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
final class TasksCoverageFixture {
    static let signalLoopCommand = """
    trap 'echo got-term-$((20+2)); exit 0' TERM; \
    trap 'echo got-int-$((30+3)); exit 0' INT; \
    echo ready-$((40+2)); \
    i=0; while [ $i -lt 600 ]; do sleep 0.1; i=$((i+1)); done
    """

    static let readyMarker = "ready-42"
    static let terminateMarker = "got-term-22"
    static let interruptMarker = "got-int-33"

    let zdotdir: URL
    let settingsStore: Dreamder.Settings

    init() throws {
        zdotdir = try makeTemporaryDirectory(label: "tasks-coverage-zdotdir")
        for name in [".zshenv", ".zprofile", ".zshrc", ".zlogin"] {
            try "".write(to: zdotdir.appending(path: name), atomically: true, encoding: .utf8)
        }
        settingsStore = Dreamder.Settings(baseURL: zdotdir.appending(path: "settings", directoryHint: .isDirectory))
        settingsStore.preferences.terminal.shell = .zsh
    }

    deinit {
        try? FileManager.default.removeItem(at: zdotdir)
    }

    var zdotdirPath: String {
        zdotdir.path(percentEncoded: false)
    }

    func makeTask(name: String = "Coverage Task", command: String) -> CETask {
        CETask(
            name: name,
            command: command,
            environmentVariables: [CETask.EnvironmentVariable(key: "ZDOTDIR", value: zdotdirPath)]
        )
    }

    func makeSignalTask(name: String = "Signal Task") -> CETask {
        makeTask(name: name, command: Self.signalLoopCommand)
    }

    func waitUntilReady(_ output: CEActiveTaskTerminalView, occurrences: Int = 1) async throws {
        try await eventually {
            output.getBufferAsString().components(separatedBy: Self.readyMarker).count - 1 >= occurrences
        }
    }

    func waitForOutput(_ output: CEActiveTaskTerminalView, containing marker: String) async throws {
        try await eventually {
            output.getBufferAsString().contains(marker)
        }
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

    static func isStopped(_ pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let written = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        return written == size && info.pbi_status == stoppedStatus
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

func makeEmptyShellIntegrationBundle(in directory: URL) throws -> Bundle {
    try #require(Bundle(path: directory.path(percentEncoded: false)))
}
