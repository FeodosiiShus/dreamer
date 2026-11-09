import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private func settingsSharedIsolated(_ body: (Dreamder.Settings) async throws -> Void) async throws {
    try await withTempDir { directory in
        try await body(Settings(baseURL: directory.appending(path: "settings", directoryHint: .isDirectory)))
    }
}

@MainActor
private func settingsSharedHost<Content: View>(
    size: NSSize = NSSize(width: 640, height: 900),
    store: Dreamder.Settings = .shared,
    @ViewBuilder _ content: () -> Content
) -> HostedView {
    let view = content()
    return HostedViewFixture.host(size: size) {
        SettingsInjector { view }.environment(\.settingsStore, store)
    }
}

@MainActor
private func settingsSharedWritePNG(to url: URL) throws {
    let representation = try #require(
        NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 8,
            pixelsHigh: 8,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    )
    let data = try #require(representation.representation(using: .png, properties: [:]))
    try data.write(to: url)
}

@MainActor
@Suite(.serialized, .uiGate)
struct SettingsSharedPagesCoverageTests {
    @Test
    func generalSettingsViewShowsTheExtensionFieldsForEveryVisibility() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        defaults.set(true, forKey: "enableOpenInCE")

        try await settingsSharedIsolated { store in
            store.preferences.general.fileExtensionsVisibility = .showAll
            let hosted = settingsSharedHost(store: store) { GeneralSettingsView(sharedDefaults: { defaults }) }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(250))
            let showAll = hosted.snapshot()
            #expect(hosted.renders())

            store.preferences.general.fileExtensionsVisibility = .showOnly
            try await hosted.settle(.milliseconds(250))
            let showOnly = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(showAll, showOnly))

            store.preferences.general.fileExtensionsVisibility = .hideOnly
            try await hosted.settle(.milliseconds(250))
            #expect(hosted.renders())

            store.preferences.general.fileExtensionsVisibility = .hideAll
            try await hosted.settle(.milliseconds(250))
            #expect(HostedView.pixelsDiffer(showOnly, hosted.snapshot()))
        }
    }

    @Test
    func generalSettingsViewRendersWithTheDefaultSharedDefaults() async throws {
        let hosted = settingsSharedHost { GeneralSettingsView() }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(250))

        #expect(hosted.renders())
    }

    @Test
    func generalSettingsViewPersistsTheFinderToggleIntoTheSharedDefaults() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }

        let view = GeneralSettingsView(sharedDefaults: { defaults })
        view.persistOpenInDreamder(true)
        #expect(defaults.bool(forKey: "enableOpenInCE"))
        view.persistOpenInDreamder(false)
        #expect(defaults.bool(forKey: "enableOpenInCE") == false)

        let unavailable = GeneralSettingsView(sharedDefaults: { nil })
        unavailable.persistOpenInDreamder(true)
        #expect(defaults.bool(forKey: "enableOpenInCE") == false)
    }

    @Test
    func generalSettingsViewAppliesTheChangedToggleAndAppearance() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let view = GeneralSettingsView(sharedDefaults: { defaults })

        view.openInDreamderChanged(false, true)
        #expect(defaults.bool(forKey: "enableOpenInCE"))

        view.appearanceChanged(.dark, .system)
        #expect(NSApp.appearance == nil)
    }

    @Test
    func navigationSettingsViewRendersBothNavigationStyles() async throws {
        try await settingsSharedIsolated { store in
            store.preferences.navigation.navigationStyle = .openInTabs
            let hosted = settingsSharedHost(size: NSSize(width: 520, height: 300), store: store) {
                NavigationSettingsView()
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(200))
            let tabs = hosted.snapshot()
            #expect(hosted.renders())

            store.preferences.navigation.navigationStyle = .openInPlace
            try await hosted.settle(.milliseconds(200))

            #expect(HostedView.pixelsDiffer(tabs, hosted.snapshot()))
        }
    }

    @Test
    func locationsSettingsViewRendersEveryLocation() async throws {
        let hosted = settingsSharedHost(size: NSSize(width: 640, height: 400)) { LocationsSettingsView() }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(250))

        #expect(hosted.renders())
    }

    @Test
    func terminalSettingsViewShowsFontControlsAndTheShellIntegrationWarning() async throws {
        try await settingsSharedIsolated { store in
            store.preferences.terminal.useTextEditorFont = true
            store.preferences.terminal.useShellIntegration = true
            let hosted = settingsSharedHost(store: store) { TerminalSettingsView() }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(250))
            let base = hosted.snapshot()
            #expect(hosted.renders())

            store.preferences.terminal.useTextEditorFont = false
            store.preferences.terminal.shell = .zsh
            store.preferences.terminal.cursorStyle = .bar
            try await hosted.settle(.milliseconds(300))
            let withFonts = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(base, withFonts))

            store.preferences.terminal.useShellIntegration = false
            store.preferences.terminal.shell = .bash
            store.preferences.terminal.cursorStyle = .underline
            try await hosted.settle(.milliseconds(300))

            #expect(HostedView.pixelsDiffer(withFonts, hosted.snapshot()))
        }
    }

    @Test
    func developerSettingsViewListsTheConfiguredLanguageServers() async throws {
        try await settingsSharedIsolated { store in
            store.preferences.developerSettings.lspBinaries = [:]
            store.preferences.developerSettings.showInternalDevelopmentInspector = false
            let hosted = settingsSharedHost(size: NSSize(width: 640, height: 600), store: store) {
                DeveloperSettingsView()
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(250))
            let empty = hosted.snapshot()
            #expect(hosted.renders())

            store.preferences.developerSettings.lspBinaries = ["swift": "/tmp/settings-shared-lsp"]
            store.preferences.developerSettings.showInternalDevelopmentInspector = true
            try await hosted.settle(.milliseconds(250))

            #expect(HostedView.pixelsDiffer(empty, hosted.snapshot()))
        }
    }

    @Test
    func developerSettingsHeaderDescribesTheNewLanguageServerForm() async throws {
        let hosted = HostedViewFixture.host(size: NSSize(width: 520, height: 120)) {
            DeveloperSettingsView().newItemHeader
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(150))

        #expect(hosted.renders())
    }

    @Test
    func developerSettingsViewPresentsTheNewLanguageServerSheet() async throws {
        let tableModel = KeyValueTableModel()
        tableModel.beginAdding()
        let hosted = settingsSharedHost(size: NSSize(width: 640, height: 600)) {
            DeveloperSettingsView(tableModel: tableModel)
        }
        defer {
            CEWorkspaceSettingsCoverageFixture.endSheets(of: hosted)
            hosted.close()
        }

        try await eventually(timeout: .seconds(30)) { hosted.window.attachedSheet != nil }
    }

    @Test
    func searchSettingsViewShowsTheExcludedPatterns() async throws {
        let model = SearchSettingsModel(patterns: []) { _ in }
        let hosted = settingsSharedHost(size: NSSize(width: 640, height: 500)) { SearchSettingsView(model: model) }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(250))
        let empty = hosted.snapshot()
        #expect(hosted.renders())

        model.ignoreGlobPatterns = [GlobPattern(value: "*.log"), GlobPattern(value: "build")]
        try await hosted.settle(.milliseconds(300))

        #expect(HostedView.pixelsDiffer(empty, hosted.snapshot()))
    }

    @Test
    func searchSettingsViewDefaultsToTheSharedModel() async throws {
        let hosted = settingsSharedHost(size: NSSize(width: 640, height: 500)) { SearchSettingsView() }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(250))

        #expect(hosted.renders())
    }

    @Test
    func searchGlobPatternItemViewRendersThePattern() async throws {
        let pattern = Binding.constant("*.generated.swift")
        let hosted = HostedViewFixture.host(size: NSSize(width: 320, height: 60)) {
            SearchSettingsIgnoreGlobPatternItemView(globPattern: pattern)
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(150))

        #expect(hosted.renders())
    }

    @Test
    func appearanceSettingsViewRendersWithoutAnImage() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let hosted = HostedViewFixture.host(size: NSSize(width: 640, height: 700)) {
            AppearanceSettingsView(defaults: defaults)
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(250))

        #expect(hosted.renders())
    }

    @Test
    func appearanceSettingsViewRendersWithTheDefaultStore() async throws {
        let hosted = HostedViewFixture.host(size: NSSize(width: 640, height: 700)) {
            AppearanceSettingsView()
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(250))

        #expect(hosted.renders())
    }

    @Test
    func appearanceSettingsViewPreviewsTheChosenImageForEveryFillMode() async throws {
        try await withTempDir { directory in
            let (defaults, suiteName) = try makeIsolatedDefaults()
            defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
            let imageURL = directory.appending(path: "background.png")
            try settingsSharedWritePNG(to: imageURL)

            let hosted = HostedViewFixture.host(size: NSSize(width: 640, height: 700)) {
                AppearanceSettingsView(defaults: defaults)
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(250))
            let withoutImage = hosted.snapshot()

            defaults.set(imageURL.path, forKey: Islands.BackgroundImageKey.path)
            defaults.set(0.6, forKey: Islands.BackgroundImageKey.opacity)
            defaults.set(Islands.Density.default.rawValue, forKey: Islands.densityKey)
            for fill in BackgroundImageFill.allCases {
                defaults.set(fill.rawValue, forKey: Islands.BackgroundImageKey.fill)
                try await hosted.settle(.milliseconds(200))
                #expect(hosted.renders())
            }
            defaults.set("unknown-fill", forKey: Islands.BackgroundImageKey.fill)
            try await hosted.settle(.milliseconds(200))

            #expect(HostedView.pixelsDiffer(withoutImage, hosted.snapshot()))
        }
    }

    @Test
    func appearanceSettingsViewChoosesAndClearsTheImage() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }

        let cancelled = AppearanceSettingsView(defaults: defaults, panels: FakeFilePanels())
        cancelled.chooseImage()
        #expect(defaults.string(forKey: Islands.BackgroundImageKey.path) == nil)

        let panels = FakeFilePanels(files: [URL(fileURLWithPath: "/tmp/settings-shared.png")])
        let chooser = AppearanceSettingsView(defaults: defaults, panels: panels)
        chooser.chooseImage()
        #expect(defaults.string(forKey: Islands.BackgroundImageKey.path) == "/tmp/settings-shared.png")
        #expect(panels.openRequests.count == 1)

        chooser.clearImage()
        #expect(defaults.string(forKey: Islands.BackgroundImageKey.path) == "")
    }

    @Test
    func appearanceSettingsViewListsItsSearchKeys() {
        #expect(AppearanceSettingsView.searchKeys.count == 8)
    }
}
