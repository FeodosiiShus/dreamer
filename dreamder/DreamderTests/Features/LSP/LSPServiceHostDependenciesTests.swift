import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite("LSPServiceHostDependencies", .uiGate)
struct LSPServiceHostDependenciesTests {
    @Test func theXCTestHostNeverDiscoversRealServers() async {
        let dependencies = LSPService.Dependencies.forHost(
            environment: [LSPService.Dependencies.testHostEnvironmentKey: "/tmp/dreamder.xctestconfiguration"]
        )

        for language in [LSPLanguage.swift, .typescript, .python, .go] {
            #expect(await dependencies.discoverBinary(language, "/tmp") == nil)
        }
        #expect(dependencies.restartBackoff == LSPService.restartBackoff)
        #expect(dependencies.observesDocumentNotifications)
    }

    @Test func theProductionHostKeepsTheLiveDependencies() {
        let dependencies = LSPService.Dependencies.forHost(environment: [:])
        let live = LSPService.Dependencies.live

        #expect(dependencies.restartBackoff == live.restartBackoff)
        #expect(dependencies.observesDocumentNotifications == live.observesDocumentNotifications)
        #expect(dependencies.notifications() === NotificationManager.shared)
    }

    @Test func theProcessEnvironmentOfTheTestHostSelectsTheTestDependencies() async {
        let dependencies = LSPService.Dependencies.forHost()

        #expect(await dependencies.discoverBinary(.swift, "/tmp") == nil)
    }
}
