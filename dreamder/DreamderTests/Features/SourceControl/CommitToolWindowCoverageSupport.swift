import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
final class CommitToolWindowCoverageAlert: NSAlert {
    var response: NSApplication.ModalResponse = .alertFirstButtonReturn

    override func runModal() -> NSApplication.ModalResponse {
        response
    }
}

@MainActor
final class CommitToolWindowCoverageAlerts {
    var response: NSApplication.ModalResponse = .alertFirstButtonReturn
    private(set) var created: [CommitToolWindowCoverageAlert] = []

    func make() -> NSAlert {
        let alert = CommitToolWindowCoverageAlert()
        alert.response = response
        created.append(alert)
        return alert
    }
}

@MainActor
final class CommitToolWindowCoverageCalls {
    var toggles: [Bool] = []
    var showDiff = 0
    var open = 0
    var rollback = 0
    var showInProject = 0
}

enum CommitToolWindowCoverageScenario {
    case singleModified
    case full
}

@MainActor
struct CommitToolWindowCoverageRig {
    static let diffName = "commit-tool-window-coverage.txt"

    let fixture: GitMergeFixture
    let workspace: WorkspaceDocument
    let manager: SourceControlManager
    let viewModel = CommitToolWindowViewModel()
    let alerts = CommitToolWindowCoverageAlerts()

    var actions: CommitToolWindowActions {
        CommitToolWindowActions(
            workspace: workspace,
            sourceControlManager: manager,
            viewModel: viewModel,
            makeAlert: alerts.make
        )
    }

    static func make(
        in directory: URL,
        scenario: CommitToolWindowCoverageScenario
    ) async throws -> CommitToolWindowCoverageRig {
        let fixture = try await GitMergeFixture(root: directory)
        try fixture.write("a.txt", "a\n")
        try fixture.write("b.txt", "b\n")
        try fixture.write("d.txt", "d\n")
        try fixture.write("sub/c.txt", "c\n")
        try fixture.write(diffName, "diff\n")
        try await fixture.commit("initial")
        var expected = 0
        switch scenario {
        case .singleModified:
            try fixture.write("a.txt", "a changed\n")
            expected = 1
        case .full:
            try fixture.write("a.txt", "a changed\n")
            try fixture.write("b.txt", "b changed\n")
            try await fixture.run("add", "b.txt")
            try FileManager.default.removeItem(at: directory.appending(path: "d.txt"))
            try fixture.write("sub/c.txt", "c changed\n")
            try fixture.write(diffName, "diff changed\n")
            try fixture.write("staged.txt", "staged\n")
            try await fixture.run("add", "staged.txt")
            try fixture.write("u.txt", "u\n")
            try fixture.write("sub/u2.txt", "u2\n")
            expected = 8
        }
        let workspace = try HostedViewFixture.makeWorkspace(in: directory)
        let manager = try #require(workspace.sourceControlManager)
        await manager.refreshAllChangedFiles()
        try await eventually { manager.changedFiles.count == expected }
        return CommitToolWindowCoverageRig(fixture: fixture, workspace: workspace, manager: manager)
    }

    func host(size: NSSize = NSSize(width: 360, height: 640)) throws -> HostedView {
        try HostedViewFixture.hostInWorkspace(workspace, size: size) {
            CommitToolWindow(viewModel: viewModel, makeAlert: alerts.make)
        }
    }

    func file(_ name: String) throws -> GitChangedFile {
        try #require(manager.changedFiles.first { $0.fileURL.lastPathComponent == name })
    }

    func names() -> [String] {
        manager.changedFiles.map(\.fileURL.lastPathComponent).sorted()
    }

    func close() {
        workspace.close()
    }
}
