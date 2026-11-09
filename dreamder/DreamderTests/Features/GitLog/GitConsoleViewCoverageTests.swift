import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct GitConsoleViewCoverageTests {
    @MainActor
    private final class GitConsoleSelectionBox {
        var isSelected = false
    }

    private func binding(_ box: GitConsoleSelectionBox) -> Binding<Bool> {
        Binding(get: { box.isSelected }, set: { box.isSelected = $0 })
    }

    private let repository = URL(fileURLWithPath: "/tmp/git-console-repo")

    @Test
    func consoleViewRendersEntriesWithErrorLinesAndFollowsTheLatest() async throws {
        let log = GitConsoleLog()
        let hosted = HostedViewFixture.host(size: NSSize(width: 500, height: 200)) {
            GitConsoleView(log: log)
        }
        defer { hosted.close() }
        try await hosted.settle()
        let empty = hosted.snapshot()

        log.record(
            command: "checkout main",
            directory: repository,
            output: "error: pathspec did not match\nhint: try again"
        )
        try await hosted.settle()
        let populated = hosted.snapshot()
        #expect(HostedView.pixelsDiffer(empty, populated))

        for index in 0..<40 {
            log.record(command: "commit \(index)", directory: repository, output: "")
        }
        try await hosted.settle()
        #expect(hosted.renders())
        #expect(log.entries.count == 41)
        #expect(log.entries.first?.errorLines == ["error: pathspec did not match", "hint: try again"])

        log.clear()
        try await hosted.settle()
        #expect(log.entries.isEmpty)
        #expect(HostedView.pixelsDiffer(populated, hosted.snapshot()))
    }

    @Test
    func consoleTabAppearsOnlyForUndismissedEntries() async throws {
        let log = GitConsoleLog()
        let box = GitConsoleSelectionBox()
        let hosted = HostedViewFixture.host(size: NSSize(width: 200, height: 60)) {
            GitConsoleTab(log: log, isSelected: binding(box))
        }
        defer { hosted.close() }
        try await hosted.settle()
        let hidden = hosted.snapshot()

        log.record(command: "fetch --all", directory: repository, output: "")
        try await hosted.settle()
        let shown = hosted.snapshot()
        #expect(HostedView.pixelsDiffer(hidden, shown))

        let tab = GitConsoleTab(log: log, isSelected: binding(box))
        tab.select()
        #expect(box.isSelected)

        tab.dismiss()
        #expect(log.isDismissed)
        #expect(box.isSelected == false)
        try await hosted.settle()
        #expect(HostedView.pixelsDiffer(shown, hosted.snapshot()))

        log.record(command: "push", directory: repository, output: "")
        #expect(log.isDismissed == false)
    }

    @Test
    func bareRemoteAndWorktreeCommandsDoNotChangeTheRepository() {
        #expect(GitConsoleLog.changesRepository("remote") == false)
        #expect(GitConsoleLog.changesRepository("worktree") == false)
    }
}
