import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
extension LanguageServerRowViewCoverageTests {
    @Test
    func theEnabledBindingReadsAndPersistsTheServerFlag() throws {
        try withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let name = CovExtGitRegistryFixtures.uniqueName()
            CovExtGitRegistryFixtures.register(name, in: manager)
            defer { manager.installedLanguageServers.removeValue(forKey: name) }
            let row = LanguageServerRowView(
                package: try CovExtGitRegistryFixtures.item(name: name),
                registryManager: manager,
                onCancel: {},
                onInstall: { _ in }
            )
            let binding = row.isEnabledBinding
            #expect(binding.wrappedValue == true)

            binding.wrappedValue = false

            #expect(binding.wrappedValue == false)
            #expect(manager.installedLanguageServers[name]?.isEnabled == false)

            binding.wrappedValue = true

            #expect(binding.wrappedValue == true)
            #expect(manager.installedLanguageServers[name]?.isEnabled == true)
        }
    }
}
