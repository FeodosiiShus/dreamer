import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct InstallViewDefaultWindowTests {
    @Test
    func theDefaultSettingsWindowSourceOnlyReadsTheApplicationsWindows() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let item = try CovExtGitRegistryFixtures.item(name: "alpha-ls")
            let operation = PackageManagerInstallOperation(package: item, steps: [])
            let hosted = HostedViewFixture.host(size: NSSize(width: 700, height: 700)) {
                LanguageServerInstallView(operation: operation, registryManager: manager)
            }
            defer { hosted.close() }

            try await hosted.settle()

            #expect(hosted.renders())
        }
    }
}
