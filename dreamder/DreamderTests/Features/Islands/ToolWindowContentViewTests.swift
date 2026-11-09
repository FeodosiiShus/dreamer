import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ToolWindowContentViewTests {
    @Test
    func hostsTheToolWindowOfEachIdentifier() async throws {
        let identifiers: [ToolWindowID] = [.commit, .structure, .run, .find, .git, .languageServices]
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            for id in identifiers {
                let hosted = try HostedViewFixture.hostInWorkspace(workspace) {
                    ToolWindowContentView(id: id).background(Color.black)
                }
                defer { hosted.close() }
                try await hosted.settle(.milliseconds(100))
                #expect(hosted.renders())
            }
        }
    }
}
