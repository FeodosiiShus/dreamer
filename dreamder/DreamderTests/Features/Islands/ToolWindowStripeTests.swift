import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ToolWindowStripeTests {
    private func failedKey(_ workspacePath: String) -> LSPService.ClientKey {
        LSPService.ClientKey(.swift, workspacePath)
    }

    @Test
    func problemCountCountsFailedServersOfTheWorkspaceOnly() {
        let states: [LSPService.ClientKey: LSPService.ServerState] = [
            LSPService.ClientKey(.swift, "/p"): .failed("crash"),
            LSPService.ClientKey(.python, "/p"): .starting,
            LSPService.ClientKey(.rust, "/p"): .failed("exit"),
            LSPService.ClientKey(.go, "/p"): .running,
            LSPService.ClientKey(.swift, "/p2"): .stopped,
            LSPService.ClientKey(.go, "/q"): .failed("other")
        ]

        #expect(LanguageServicesStripeButton.problemCount(in: states, workspacePath: "/p") == 2)
        #expect(LanguageServicesStripeButton.problemCount(in: states, workspacePath: "/q") == 1)
        #expect(LanguageServicesStripeButton.problemCount(in: states, workspacePath: "/none") == 0)
        #expect(LanguageServicesStripeButton.problemCount(in: states, workspacePath: nil) == 3)
        #expect(LanguageServicesStripeButton.problemCount(in: [:], workspacePath: nil) == 0)
    }

    @Test
    func toggleSplitMovesAWindowBetweenTheMainAndSplitGroups() {
        let manager = ToolWindowManager()

        manager.toggleSplit(.structure)
        #expect(manager.isSplit(.structure))

        manager.toggleSplit(.structure)
        #expect(!manager.isSplit(.structure))
    }

    @Test
    func toggleSplitKeepsAVisibleWindowVisible() {
        let manager = ToolWindowManager()
        manager.show(.structure)

        manager.toggleSplit(.structure)

        #expect(manager.isVisible(.structure))
        #expect(manager.visible(on: .left, side: .split) == .structure)
        #expect(manager.visible(on: .left, side: .main) == nil)
    }

    @Test
    func stripeRendersTheMainGroupsWithoutADivider() async throws {
        try await withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let hosted = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 60, height: 500)) {
                ToolWindowStripe()
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))

            #expect(hosted.renders())
        }
    }

    @Test
    func stripeShowsADividerBetweenMainAndSplitButtons() async throws {
        try await withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let plain = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 60, height: 500)) {
                ToolWindowStripe()
            }
            defer { plain.close() }
            try await plain.settle(.milliseconds(100))
            let before = plain.snapshot()

            workspace.toolWindowManager.setSplit(.structure, true)
            workspace.toolWindowManager.setSplit(.find, true)
            try await plain.settle(.milliseconds(100))

            #expect(HostedView.pixelsDiffer(before, plain.snapshot()))
        }
    }

    @Test
    func stripeBackgroundFollowsTheBackgroundImageSettings() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        try await withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let hosted = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 60, height: 500)) {
                ToolWindowStripe().defaultAppStorage(defaults)
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))
            let opaque = hosted.snapshot()

            defaults.set("/tmp/background.png", forKey: Islands.BackgroundImageKey.path)
            defaults.set(0.5, forKey: Islands.BackgroundImageKey.opacity)
            try await hosted.settle(.milliseconds(100))

            #expect(HostedView.pixelsDiffer(opaque, hosted.snapshot()))
        }
    }

    @Test
    func stripeButtonShowsTheSelectionBackground() async throws {
        try await withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            workspace.toolWindowManager.hideAll()
            let hosted = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 60, height: 60)) {
                ToolWindowStripeButton(id: .find)
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))
            let idle = hosted.snapshot()

            workspace.toolWindowManager.show(.find)
            try await hosted.settle(.milliseconds(100))

            #expect(HostedView.pixelsDiffer(idle, hosted.snapshot()))
        }
    }

    @Test
    func splitMenuItemRendersForMainAndSplitWindows() async throws {
        try await withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let hosted = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 200, height: 40)) {
                ToolWindowSplitMenuItem(id: .structure)
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))
            let main = hosted.snapshot()

            workspace.toolWindowManager.toggleSplit(.structure)
            try await hosted.settle(.milliseconds(100))

            #expect(workspace.toolWindowManager.isSplit(.structure))
            #expect(HostedView.pixelsDiffer(main, hosted.snapshot()))
        }
    }

    @Test
    func languageServicesButtonShowsABadgeForFailedServersWhileUnselected() async throws {
        try await withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            workspace.toolWindowManager.hideAll()
            let path = try #require(workspace.fileURL?.absolutePath)
            let healthy = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 60, height: 60)) {
                LanguageServicesStripeButton(serverStates: [:])
            }
            defer { healthy.close() }
            let failing = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 60, height: 60)) {
                LanguageServicesStripeButton(serverStates: [failedKey(path): .failed("crash")])
            }
            defer { failing.close() }
            try await healthy.settle(.milliseconds(100))
            try await failing.settle(.milliseconds(100))

            #expect(HostedView.pixelsDiffer(healthy.snapshot(), failing.snapshot()))
        }
    }

    @Test
    func languageServicesButtonHidesTheBadgeWhileSelected() async throws {
        try await withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            workspace.toolWindowManager.hideAll()
            workspace.toolWindowManager.show(.languageServices)
            let path = try #require(workspace.fileURL?.absolutePath)
            let healthy = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 60, height: 60)) {
                LanguageServicesStripeButton(serverStates: [:])
            }
            defer { healthy.close() }
            let failing = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 60, height: 60)) {
                LanguageServicesStripeButton(serverStates: [failedKey(path): .failed("crash")])
            }
            defer { failing.close() }
            try await healthy.settle(.milliseconds(100))
            try await failing.settle(.milliseconds(100))

            #expect(!HostedView.pixelsDiffer(healthy.snapshot(), failing.snapshot()))
        }
    }
}
