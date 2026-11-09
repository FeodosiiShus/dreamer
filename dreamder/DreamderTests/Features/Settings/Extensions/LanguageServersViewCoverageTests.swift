import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct LanguageServersViewCoverageTests {
    private func host(_ model: LanguageServersModel) -> HostedView {
        HostedViewFixture.host(size: NSSize(width: 800, height: 600)) {
            LanguageServersView(model: model)
        }
    }

    @Test
    func installingASupportedPackagePreparesTheSheetOperation() async throws {
        try withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let model = LanguageServersModel(registryManager: manager)
            let item = try CovExtGitRegistryFixtures.item(name: "alpha-ls")

            model.install(item)

            #expect(model.selectedInstall?.package.name == "alpha-ls")
        }
    }

    @Test
    func installingAnUnsupportedPackageShowsTheErrorAndKeepsNoSheet() async throws {
        try withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let model = LanguageServersModel(registryManager: manager)
            let item = try CovExtGitRegistryFixtures.item(name: "tool", sourceID: "pkg:nuget/Tool@1.0.0")
            let modalsBefore = DreamderHeadless.suppressedModals.count

            model.install(item)

            #expect(model.selectedInstall == nil)
            #expect(DreamderHeadless.suppressedModals.count > modalsBefore)
        }
    }

    @Test
    func searchTextFiltersTheRegistryAndClearingRestoresIt() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            manager.setRegistryItems([
                try CovExtGitRegistryFixtures.item(name: "alpha-ls"),
                try CovExtGitRegistryFixtures.item(name: "zeta-formatter")
            ])
            let model = LanguageServersModel(registryManager: manager)

            model.searchText = "alpha"
            try await eventually { model.searchModel.items?.map(\.name) == ["alpha-ls"] }

            model.searchText = ""
            try await eventually { model.searchModel.items == nil }
        }
    }

    @Test
    func listRendersTheRegistryRowsAndTheDownloadSpinner() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            manager.setRegistryItems([
                try CovExtGitRegistryFixtures.item(name: "alpha-ls"),
                try CovExtGitRegistryFixtures.item(name: "zeta-formatter")
            ])
            let model = LanguageServersModel(registryManager: manager)
            let hosted = host(model)
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())
            let idle = hosted.snapshot()

            manager.isDownloadingRegistry = true
            try await hosted.settle()
            let downloading = hosted.snapshot()
            manager.isDownloadingRegistry = false

            #expect(HostedView.pixelsDiffer(idle, downloading))
        }
    }

    @Test
    func searchingReRendersTheListWithTheMatches() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            manager.setRegistryItems([
                try CovExtGitRegistryFixtures.item(name: "alpha-ls"),
                try CovExtGitRegistryFixtures.item(name: "zeta-formatter")
            ])
            let model = LanguageServersModel(registryManager: manager)
            let hosted = host(model)
            defer { hosted.close() }
            try await hosted.settle()
            let all = hosted.snapshot()

            model.searchText = "zeta"
            try await eventually { model.searchModel.items?.map(\.name) == ["zeta-formatter"] }
            try await hosted.settle()

            #expect(HostedView.pixelsDiffer(all, hosted.snapshot()))
        }
    }

    @Test
    func selectingAnInstallPresentsTheInstallSheet() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let item = try CovExtGitRegistryFixtures.item(name: "alpha-ls")
            manager.setRegistryItems([item])
            let model = LanguageServersModel(registryManager: manager)
            let hosted = host(model)
            defer { hosted.close() }
            try await hosted.settle()

            model.install(item)
            try await hosted.settle()

            #expect(model.selectedInstall?.package.name == "alpha-ls")
            model.selectedInstall = nil
            try await hosted.settle()
        }
    }

    @Test
    func infoStringLinksTheMasonRegistry() async throws {
        try withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let view = LanguageServersView(model: LanguageServersModel(registryManager: manager))

            let info = view.getInfoString()

            #expect(String(info.characters).hasPrefix("Dreamder makes use of the Mason Registry"))
            #expect(info.runs.contains { $0.link == URL(string: "https://mason-registry.dev/") })
        }
    }
}
