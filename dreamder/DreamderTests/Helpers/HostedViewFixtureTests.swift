import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct HostedViewFixtureTests {
    @MainActor
    private final class Seen {
        var workspaceName: String?
        var editorCount: Int?
    }

    @Observable
    @MainActor
    final class Toggle {
        var isOn = false
    }

    @Test
    func hostedViewsRenderIntoAHiddenWindowWithVisiblePixels() async throws {
        let hosted = HostedViewFixture.host(size: NSSize(width: 200, height: 100)) {
            Text("Hello harness").foregroundStyle(.red).padding()
        }
        defer { hosted.close() }
        try await hosted.settle()

        #expect(hosted.window.level == DreamderHeadless.hiddenLevel)
        #expect(hosted.renders())
    }

    @Test
    func changingObservedStateReRendersTheView() async throws {
        let toggle = Toggle()
        let hosted = HostedViewFixture.host(size: NSSize(width: 200, height: 100)) {
            ToggleProbe(toggle: toggle)
        }
        defer { hosted.close() }
        try await hosted.settle()
        let before = hosted.snapshot()

        toggle.isOn = true
        try await hosted.settle()
        let after = hosted.snapshot()

        #expect(HostedView.pixelsDiffer(before, after))
    }

    @Test
    func workspaceHostingInjectsTheEnvironmentTheWindowRootUses() async throws {
        try await withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let seen = Seen()
            let hosted = try HostedViewFixture.hostInWorkspace(workspace) {
                EnvironmentProbe(seen: seen)
            }
            defer { hosted.close() }
            try await hosted.settle()

            #expect(seen.workspaceName == directory.lastPathComponent)
            #expect(seen.editorCount == workspace.editorManager?.flattenedEditors.count)
        }
    }

    private struct ToggleProbe: View {
        let toggle: Toggle

        var body: some View {
            Rectangle()
                .fill(toggle.isOn ? Color.green : Color.blue)
                .frame(width: 100, height: 50)
        }
    }

    private struct EnvironmentProbe: View {
        @Environment(WorkspaceDocument.self) private var workspace
        @Environment(EditorManager.self) private var editorManager
        let seen: Seen

        var body: some View {
            Color.clear.onAppear {
                seen.workspaceName = workspace.fileURL?.lastPathComponent
                seen.editorCount = editorManager.flattenedEditors.count
            }
        }
    }
}
