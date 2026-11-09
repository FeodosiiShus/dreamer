import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct TrustProjectCommandTests {
    @MainActor
    private final class ConfirmRecorder {
        var asked: [URL] = []

        func confirm(_ root: URL) async -> Bool {
            asked.append(root)
            return true
        }
    }

    @MainActor
    private struct Harness {
        let workspace: WorkspaceDocument
        let controller: DreamderWindowController
        let window: NSWindow

        func close() {
            window.close()
            workspace.close()
        }
    }

    private func makeHarness(in directory: URL) throws -> Harness {
        let workspace = WorkspaceDocument()
        try workspace.read(from: directory, ofType: "")
        workspace.makeWindowControllers()
        let controller = try #require(workspace.windowControllers.first as? DreamderWindowController)
        let window = try #require(controller.window)
        window.isReleasedWhenClosed = false
        return Harness(workspace: workspace, controller: controller, window: window)
    }

    @Test
    func theCommandAsksForTheActiveWorkspaceRoot() async throws {
        try await withTempDir { directory in
            try await withIsolatedDefaults { defaults in
                let harness = try makeHarness(in: directory)
                defer { harness.close() }
                let recorder = ConfirmRecorder()
                let trust = WorkspaceTrust(defaults: defaults, confirm: { await recorder.confirm($0) })
                let root = try #require(harness.workspace.fileURL)
                #expect(!trust.isTrusted(root))

                #expect(await harness.controller.requestProjectTrust(using: trust))

                #expect(recorder.asked == [root])
                #expect(trust.isTrusted(root))
                #expect(WorkspaceTrust(defaults: defaults).isTrusted(root))
            }
        }
    }

    @Test
    func theCommandDoesNothingWithoutAWorkspace() async throws {
        try await withTempDir { directory in
            try await withIsolatedDefaults { defaults in
                let harness = try makeHarness(in: directory)
                defer { harness.close() }
                harness.controller.workspace = nil
                harness.controller.trustProject(nil)
                CommandManager.shared.executeCommand(DreamderWindowController.trustProjectCommandID)
                let recorder = ConfirmRecorder()
                let trust = WorkspaceTrust(defaults: defaults, confirm: { await recorder.confirm($0) })

                #expect(await harness.controller.requestProjectTrust(using: trust) == false)
                #expect(recorder.asked.isEmpty)
            }
        }
    }

    @Test
    func theCommandIsRegisteredForThePalette() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }

            let titles = CommandManager.shared.commands.map(\.title)
            #expect(titles.contains("Trust Project\u{2026}"))
            #expect(DreamderWindowController.instancesRespond(to: #selector(DreamderWindowController.trustProject(_:))))
        }
    }
}
