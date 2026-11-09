import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite("LSPService workspace trust restart", .uiGate)
struct LSPServiceWorkspaceTrustTests {
    let fixture = LSPServiceFixture()

    @Test
    func restartingAWorkspaceRestartsItsRunningAndFailedServersOnly() async throws {
        let service = fixture.makeService()
        _ = try await service.startServer(for: .python, workspacePath: "/ws")
        _ = try await service.startServer(for: .rust, workspacePath: "/other")
        _ = try await service.startServer(for: .swift, workspacePath: "/ws")
        try await service.stopServer(forLanguage: .swift, workspacePath: "/ws")
        fixture.createFailure = LSPServiceFixtureFailure.creation
        _ = try? await service.startServer(for: .go, workspacePath: "/ws")
        fixture.createFailure = nil
        let before = fixture.discoveries.count
        let creationFailure = String(describing: LSPServiceFixtureFailure.creation)
        #expect(service.serverStates[.init(.go, "/ws")] == .failed(creationFailure))

        await service.restartServers(inWorkspace: "/ws")

        let restarted = fixture.discoveries.dropFirst(before)
        #expect(Set(restarted.map(\.language)) == [.python, .go])
        #expect(restarted.allSatisfy { $0.workspacePath == "/ws" })
        #expect(service.serverStates[.init(.python, "/ws")] == .running)
        #expect(service.serverStates[.init(.go, "/ws")] == .running)
        #expect(service.serverStates[.init(.swift, "/ws")] == .stopped)
        #expect(service.serverStates[.init(.rust, "/other")] == .running)
    }

    @Test
    func aWorkspaceWithoutServersChangesNothing() async throws {
        let service = fixture.makeService()
        _ = try await service.startServer(for: .python, workspacePath: "/ws")
        let before = fixture.discoveries.count

        await service.restartServers(inWorkspace: "/empty")

        #expect(fixture.discoveries.count == before)
    }
}
