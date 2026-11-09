import AppKit
import Foundation
@testable import Dreamder

@MainActor
final class GitCloneCoverageRecorder {
    struct Alert: Equatable {
        let message: String
        let info: String
        let buttons: [String]
        let style: NSAlert.Style
    }

    var alerts: [Alert] = []
    var panels: [SavePanelRequest] = []
    var destination: URL?
    var clipboard: String?
    var cloned: [URL] = []
    var branchViews: [URL] = []
    var documents: [URL] = []

    func services(
        processRunner: any ProcessRunning = ProcessRunner(),
        gitClientRunner: (any ProcessRunning)? = nil
    ) -> GitCloneServices {
        var services = GitCloneServices()
        services.processRunner = processRunner
        services.clipboardText = { [self] in clipboard }
        services.filePanels = self
        services.presentAlert = { [self] alert in
            alerts.append(Alert(
                message: alert.messageText,
                info: alert.informativeText,
                buttons: alert.buttons.map(\.title),
                style: alert.alertStyle
            ))
        }
        if let gitClientRunner {
            services.makeGitClient = {
                GitClient(
                    directoryURL: $0,
                    shellClient: .live(),
                    processRunner: gitClientRunner,
                    gitExecutable: URL(fileURLWithPath: "/usr/bin/git")
                )
            }
        }
        return services
    }
}

extension GitCloneCoverageRecorder: FilePanelPresenting {
    func chooseFiles(_ request: OpenPanelRequest) -> [URL] {
        []
    }

    func chooseSaveLocation(_ request: SavePanelRequest) -> URL? {
        panels.append(request)
        return destination
    }
}

nonisolated final class GitCloneCoverageRunner: ProcessRunning, Sendable {
    enum Which: Sendable {
        case found
        case missing
        case launchFails
    }

    enum Ending: Sendable {
        case exit(Int32)
        case hold
        case fail(any Error)
    }

    private let which: Which
    private let lines: [String]
    private let ending: Ending
    private let removesDestination: Bool

    init(
        which: Which = .found,
        lines: [String] = [],
        ending: Ending = .exit(0),
        removesDestination: Bool = false
    ) {
        self.which = which
        self.lines = lines
        self.ending = ending
        self.removesDestination = removesDestination
    }

    func run(_ invocation: ProcessInvocation) async throws -> ProcessOutput {
        switch which {
        case .found:
            return ProcessOutput(exitCode: 0)
        case .missing:
            return ProcessOutput(exitCode: 1)
        case .launchFails:
            throw ProcessRunnerError.launchFailed(executable: invocation.executable.path, reason: "unavailable")
        }
    }

    func stream(_ invocation: ProcessInvocation) -> AsyncThrowingStream<ProcessEvent, any Error> {
        AsyncThrowingStream { continuation in
            if removesDestination, let destination = invocation.arguments.last {
                try? FileManager.default.removeItem(atPath: destination)
            }
            for line in lines {
                continuation.yield(.line(.standardError, line))
            }
            switch ending {
            case .exit(let code):
                continuation.yield(.exit(code: code, terminatedBySignal: false))
                continuation.finish()
            case .hold:
                break
            case .fail(let error):
                continuation.finish(throwing: error)
            }
        }
    }
}

nonisolated enum GitCloneCoverageOrigin {
    static func makeBare(in directory: URL, branches: [String]) async throws -> URL {
        let work = directory.appending(path: "origin-work", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let fixture = try await GitMergeFixture(root: work)
        try fixture.write("readme.txt", "main\n")
        try await fixture.commit("initial")
        for branch in branches {
            try await fixture.run("checkout", "-q", "-b", branch)
            try fixture.write("\(branch).txt", "\(branch)\n")
            try await fixture.commit(branch)
            try await fixture.run("checkout", "-q", "main")
        }
        let bare = directory.appending(path: "origin.git", directoryHint: .isDirectory)
        try await fixture.run(
            "clone", "-q", "--bare",
            work.path(percentEncoded: false),
            bare.path(percentEncoded: false)
        )
        return bare
    }

    static func clone(of origin: URL, into destination: URL) async throws {
        let fixture = GitMergeFixture(existing: destination.deletingLastPathComponent())
        try await fixture.run(
            "clone", "-q",
            origin.path(percentEncoded: false),
            destination.path(percentEncoded: false)
        )
    }
}
