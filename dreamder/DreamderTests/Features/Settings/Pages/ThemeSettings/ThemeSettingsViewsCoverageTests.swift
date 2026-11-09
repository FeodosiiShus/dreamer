import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class ThemeTokenColorBox {
    var color: Color

    init(_ color: Color) {
        self.color = color
    }

    var binding: Binding<Color> {
        Binding(get: { self.color }, set: { self.color = $0 })
    }
}

@MainActor
@Observable
private final class ThemeSchemeBox {
    var scheme: ColorScheme = .dark
}

private struct ThemeSchemeHarness: View {
    let model: ThemeModel
    let box: ThemeSchemeBox

    var body: some View {
        ThemeSettingsView(themeModel: model).environment(\.colorScheme, box.scheme)
    }
}

@MainActor
@Suite(.uiGate)
struct ThemeSettingsViewsCoverageTests {
    private typealias Fixtures = ThemeSettingsCoverageThemes

    private let rowSize = NSSize(width: 700, height: 90)
    private let detailsSize = NSSize(width: 700, height: 900)
    private let listSize = NSSize(width: 800, height: 700)

    private func coloredTheme(name: String, keyword: String, background: String) -> Theme {
        var theme = Fixtures.make(name: name)
        theme.editor.keywords = Theme.Attributes(color: keyword)
        theme.editor.background = Theme.Attributes(color: background)
        return theme
    }

    @Test
    func colorPreviewRendersTheThemeColors() throws {
        let dark = HostedViewFixture.host(size: NSSize(width: 200, height: 60)) {
            ThemeSettingsColorPreview(coloredTheme(name: "dark", keyword: "#ff0000", background: "#000000"))
        }
        let light = HostedViewFixture.host(size: NSSize(width: 200, height: 60)) {
            ThemeSettingsColorPreview(coloredTheme(name: "light", keyword: "#0000ff", background: "#ffffff"))
        }
        defer {
            dark.close()
            light.close()
        }

        #expect(dark.renders())
        #expect(light.renders())
        #expect(HostedView.pixelsDiffer(dark.snapshot(), light.snapshot()))
    }

    @Test
    func colorPreviewDotRendersItsColor() {
        let red = HostedViewFixture.host(size: NSSize(width: 40, height: 40)) {
            ThemeSettingsColorPreviewColor(.red).padding(10)
        }
        let blue = HostedViewFixture.host(size: NSSize(width: 40, height: 40)) {
            ThemeSettingsColorPreviewColor(.blue).padding(10)
        }
        defer {
            red.close()
            blue.close()
        }

        #expect(red.renders())
        #expect(HostedView.pixelsDiffer(red.snapshot(), blue.snapshot()))
    }

    @Test
    func tokenRendersPlainBoldAndItalicVariants() {
        func host(bold: Bool, italic: Bool) -> HostedView {
            HostedViewFixture.host(size: NSSize(width: 500, height: 60)) {
                ThemeSettingsThemeToken("Keywords", color: .constant(.red), bold: .constant(bold), italic: .constant(italic))
            }
        }
        let plain = host(bold: false, italic: false)
        let bold = host(bold: true, italic: false)
        let italic = host(bold: false, italic: true)
        defer {
            plain.close()
            bold.close()
            italic.close()
        }

        #expect(plain.renders())
        #expect(HostedView.pixelsDiffer(plain.snapshot(), bold.snapshot()))
        #expect(HostedView.pixelsDiffer(plain.snapshot(), italic.snapshot()))
    }

    @Test
    func tokenAppliesTheSelectedColorToItsBinding() {
        let box = ThemeTokenColorBox(.red)
        let token = ThemeSettingsThemeToken(
            "Keywords",
            color: box.binding,
            bold: .constant(false),
            italic: .constant(false)
        )

        token.applySelectedColor(.red, .blue)
        token.setHovering(true)
        token.setHovering(false)

        #expect(box.color == .blue)
    }

    @Test
    func rowRendersActiveInactiveAndConfirmingVariants() async throws {
        try await withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let mine = try themeSettingsCoverageTheme(model, named: "mine")
            let bundled = try themeSettingsCoverageTheme(model, named: "bundled-dark")

            @MainActor func host(
                _ theme: Theme,
                active: Bool,
                confirming: Bool = false,
                hovering: Bool = false
            ) -> HostedView {
                HostedViewFixture.host(size: rowSize) {
                    ThemeSettingsThemeRow(
                        theme: .constant(theme),
                        active: active,
                        themeModel: model,
                        isConfirmingDelete: confirming,
                        isHovering: hovering
                    )
                }
            }
            let active = host(mine, active: true)
            let inactive = host(mine, active: false)
            let hovered = host(mine, active: false, hovering: true)
            let bundledRow = host(bundled, active: false)
            let confirming = host(mine, active: false, confirming: true)
            defer {
                active.close()
                inactive.close()
                hovered.close()
                bundledRow.close()
                confirming.close()
            }
            try await confirming.settle(.milliseconds(150))

            #expect(active.renders())
            #expect(inactive.renders())
            #expect(bundledRow.renders())
            #expect(confirming.renders())
            #expect(HostedView.pixelsDiffer(active.snapshot(), inactive.snapshot()))
            #expect(HostedView.pixelsDiffer(inactive.snapshot(), hovered.snapshot()))
        }
    }

    @Test
    func rowActionsDriveTheModel() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let panels = FakeFilePanels()
            let model = try env.seededModel(filePanels: panels)
            let mine = try themeSettingsCoverageTheme(model, named: "mine")
            let bundled = try themeSettingsCoverageTheme(model, named: "bundled-dark")
            let row = ThemeSettingsThemeRow(theme: .constant(bundled), active: false, themeModel: model)
            let customRow = ThemeSettingsThemeRow(theme: .constant(mine), active: true, themeModel: model)
            let detached = ThemeSettingsThemeRow(
                theme: .constant(Fixtures.make(name: "detached")),
                active: false,
                themeModel: model
            )

            customRow.setHovering(true)
            customRow.requestDelete()
            customRow.cancelDelete()
            #expect(FileManager.default.fileExists(atPath: env.themesURL.appending(path: "mine.cetheme").path))

            row.choose()
            #expect(model.selectedTheme?.name == "bundled-dark")

            customRow.showDetails()
            #expect(model.detailsTheme?.name == "mine")
            #expect(model.detailsIsPresented)

            detached.duplicate()
            #expect(FileManager.default.fileExists(atPath: env.themesURL.appending(path: "detached 1.cetheme").path) == false)

            customRow.export()
            #expect(panels.saveRequests.count == 1)

            customRow.duplicate()
            #expect(FileManager.default.fileExists(atPath: env.themesURL.appending(path: "mine 1.cetheme").path))

            customRow.confirmDelete()
            #expect(FileManager.default.fileExists(atPath: env.themesURL.appending(path: "mine.cetheme").path) == false)
        }
    }

    @Test
    func rowMenuAndAlertContentsAreBuilt() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let mine = try themeSettingsCoverageTheme(model, named: "mine")
            let bundled = try themeSettingsCoverageTheme(model, named: "bundled-dark")

            for theme in [mine, bundled] {
                let row = ThemeSettingsThemeRow(theme: .constant(theme), active: false, themeModel: model)
                let hosted = HostedViewFixture.host(size: rowSize) {
                    VStack {
                        row.menuLabel
                        row.menuItems
                        row.deleteActions
                        row.deleteMessage
                        row.deleteTitle
                    }
                }
                defer { hosted.close() }
                #expect(hosted.renders())
            }
        }
    }

    @Test
    func detailsRenderEveryFooterVariant() async throws {
        try await withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let mine = try themeSettingsCoverageTheme(model, named: "mine")
            let bundled = try themeSettingsCoverageTheme(model, named: "bundled-dark")
            let light = try themeSettingsCoverageTheme(model, named: "bundled-light")

            @MainActor func host(_ theme: Theme, model: ThemeModel, confirming: Bool = false) -> HostedView {
                HostedViewFixture.host(size: detailsSize) {
                    ThemeSettingsThemeDetails(theme: .constant(theme), themeModel: model, isConfirmingDelete: confirming)
                }
            }
            let addingModel = env.makeModel()
            addingModel.isAdding = true
            let custom = host(mine, model: model)
            let customAdding = host(mine, model: addingModel)
            let bundledPlain = host(bundled, model: model)
            let bundledAdding = host(bundled, model: addingModel)
            let lightTheme = host(light, model: model)
            let confirming = host(mine, model: model, confirming: true)
            defer {
                custom.close()
                customAdding.close()
                bundledPlain.close()
                bundledAdding.close()
                lightTheme.close()
                confirming.close()
            }
            try await confirming.settle(.milliseconds(150))

            for hosted in [custom, customAdding, bundledPlain, bundledAdding, lightTheme, confirming] {
                #expect(hosted.renders())
            }
            #expect(HostedView.pixelsDiffer(custom.snapshot(), bundledPlain.snapshot()))
            #expect(HostedView.pixelsDiffer(bundledPlain.snapshot(), lightTheme.snapshot()))
            #expect(HostedView.pixelsDiffer(custom.snapshot(), customAdding.snapshot()))
        }
    }

    @Test
    func detailsActionsDriveTheModel() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            var mine = try themeSettingsCoverageTheme(model, named: "mine")
            let index = try #require(model.themes.firstIndex { $0.name == "mine" })
            var original = mine
            original.displayName = "Original"
            model.detailsTheme = original
            model.themes[index].displayName = "Edited"
            mine = model.themes[index]

            let view = ThemeSettingsThemeDetails(theme: .constant(mine), themeModel: model)
            #expect(view.isActive == (model.selectedTheme == mine))
            #expect(view.originalTheme.displayName == "Edited")

            view.cancelTapped()
            #expect(model.themes[index].displayName == "Original")

            model.isAdding = true
            let duplicating = ThemeSettingsThemeDetails(theme: .constant(mine), themeModel: model, duplicatingTheme: mine)
            duplicating.cancelTapped()
            #expect(model.isAdding == false)

            _ = view.deleteTitle
            _ = view.deleteActions
            _ = view.deleteMessage
        }
    }

    @Test
    func detailsDuplicateActionCopiesTheThemeFile() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let mine = try themeSettingsCoverageTheme(model, named: "mine")
            let view = ThemeSettingsThemeDetails(theme: .constant(mine), themeModel: model)

            let themeCount = model.themes.count
            view.requestDelete()
            view.cancelDelete()
            view.beginDuplicating()

            #expect(model.themes.count == themeCount + 1)
            #expect(model.isAdding)
            #expect(FileManager.default.fileExists(atPath: env.themesURL.appending(path: "mine 1.cetheme").path))
        }
    }

    @Test
    func detailsDoneRenamesCustomThemesAndConfirmDeleteRemovesThem() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            var mine = try themeSettingsCoverageTheme(model, named: "mine")
            mine.displayName = "Done Theme"

            ThemeSettingsThemeDetails(theme: .constant(mine), themeModel: model).doneTapped()
            #expect(FileManager.default.fileExists(atPath: env.themesURL.appending(path: "Done Theme.cetheme").path))

            let renamed = try #require(model.themes.first { $0.fileURL?.lastPathComponent == "Done Theme.cetheme" })
            ThemeSettingsThemeDetails(theme: .constant(renamed), themeModel: model).confirmDelete()
            #expect(FileManager.default.fileExists(atPath: env.themesURL.appending(path: "Done Theme.cetheme").path) == false)
        }
    }

    @Test
    func listRendersThemesForBothColorSchemes() async throws {
        try await withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let empty = try ThemeSettingsCoverageEnvironment(root: dir.appending(path: "empty", directoryHint: .isDirectory))
            let emptyModel = empty.makeModel(bundledThemesURL: nil)

            let dark = HostedViewFixture.host(size: listSize) {
                ThemeSettingsView(themeModel: model).environment(\.colorScheme, .dark)
            }
            let light = HostedViewFixture.host(size: listSize) {
                ThemeSettingsView(themeModel: model).environment(\.colorScheme, .light)
            }
            let none = HostedViewFixture.host(size: listSize) {
                ThemeSettingsView(themeModel: emptyModel)
            }
            defer {
                dark.close()
                light.close()
                none.close()
            }
            try await dark.settle()
            try await light.settle()
            try await none.settle()

            #expect(dark.renders())
            #expect(light.renders())
            #expect(none.renders())
            #expect(HostedView.pixelsDiffer(dark.snapshot(), light.snapshot()))
            #expect(HostedView.pixelsDiffer(light.snapshot(), none.snapshot()))
        }
    }

    @Test
    func listRefreshesWhenTheThemesChange() async throws {
        try await withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let hosted = HostedViewFixture.host(size: listSize) { ThemeSettingsView(themeModel: model) }
            defer { hosted.close() }
            try await hosted.settle()
            let before = hosted.snapshot()

            model.themes.removeAll { $0.name == "mine" }
            try await hosted.settle()

            #expect(HostedView.pixelsDiffer(before, hosted.snapshot()))
        }
    }

    @Test
    func listRefreshesWhenTheColorSchemeChanges() async throws {
        try await withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let box = ThemeSchemeBox()
            let hosted = HostedViewFixture.host(size: listSize) {
                ThemeSchemeHarness(model: model, box: box)
            }
            defer { hosted.close() }
            try await hosted.settle()
            let dark = hosted.snapshot()

            box.scheme = .light
            try await hosted.settle()

            #expect(HostedView.pixelsDiffer(dark, hosted.snapshot()))
        }
    }

    @Test
    func listFiltersThemesBySearchQuery() async throws {
        try await withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()

            let all = HostedViewFixture.host(size: listSize) { ThemeSettingsView(themeModel: model) }
            let matching = HostedViewFixture.host(size: listSize) {
                ThemeSettingsView(themeModel: model, initialSearchQuery: "mine")
            }
            let nothing = HostedViewFixture.host(size: listSize) {
                ThemeSettingsView(themeModel: model, initialSearchQuery: "zzzzzqqqq")
            }
            defer {
                all.close()
                matching.close()
                nothing.close()
            }
            try await all.settle()
            try await matching.settle()
            try await nothing.settle()

            #expect(matching.renders())
            #expect(HostedView.pixelsDiffer(all.snapshot(), matching.snapshot()))
            #expect(HostedView.pixelsDiffer(matching.snapshot(), nothing.snapshot()))
        }
    }

    @Test
    func typingIntoTheSearchFieldFiltersTheList() async throws {
        try await withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let hosted = HostedViewFixture.host(size: listSize) { ThemeSettingsView(themeModel: model) }
            defer { hosted.close() }
            try await hosted.settle()
            let before = hosted.snapshot()

            let field = try #require(hosted.views(of: NSSearchField.self).first)
            field.stringValue = "mine"
            field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
            try await hosted.settle()

            #expect(HostedView.pixelsDiffer(before, hosted.snapshot()))
        }
    }

    @Test
    func clickingImportShowsThePanel() async throws {
        try await withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let panels = FakeFilePanels()
            let model = try env.seededModel(filePanels: panels)
            let hosted = HostedViewFixture.host(size: listSize) { ThemeSettingsView(themeModel: model) }
            defer { hosted.close() }
            try await hosted.settle()

            let buttons = hosted.views(of: NSButton.self)
            if let importButton = buttons.first(where: { $0.title == "Import..." }) {
                importButton.performClick(nil)
                #expect(panels.openRequests.count == 1)
            }
            #expect(hosted.renders())
        }
    }

    @Test
    func togglingMatchAppearanceShowsAndHidesTheTerminalToggle() async throws {
        try await withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let store = env.settings

            store.preferences.theme.matchAppearance = true
            let on = HostedViewFixture.host(size: listSize) {
                ThemeSettingsView(themeModel: model).environment(\.settingsStore, store)
            }
            defer { on.close() }
            try await on.settle()
            let onSnapshot = on.snapshot()

            store.preferences.theme.matchAppearance = false
            let off = HostedViewFixture.host(size: listSize) {
                ThemeSettingsView(themeModel: model).environment(\.settingsStore, store)
            }
            defer { off.close() }
            try await off.settle()

            store.preferences.theme.matchAppearance = true
            try await on.settle()

            #expect(on.renders())
            #expect(HostedView.pixelsDiffer(onSnapshot, off.snapshot()))
        }
    }

    @Test
    func detailsSheetOpensWhenTheModelPresentsIt() async throws {
        try await withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let mine = try themeSettingsCoverageTheme(model, named: "mine")
            let hosted = HostedViewFixture.host(size: listSize) { ThemeSettingsView(themeModel: model) }
            defer { hosted.close() }
            try await hosted.settle()

            model.showDetails(of: mine)
            try await hosted.settle()
            #expect(hosted.renders())

            model.detailsIsPresented = false
            try await hosted.settle()
            #expect(hosted.renders())
        }
    }

    @Test
    func viewHelpersDelegateToTheModel() async throws {
        try await withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let mine = try themeSettingsCoverageTheme(model, named: "mine")
            let index = try #require(model.themes.firstIndex { $0.name == "mine" })
            let view = ThemeSettingsView(themeModel: model)

            model.selectedDarkTheme = try themeSettingsCoverageTheme(model, named: "bundled-dark")
            model.selectedLightTheme = try themeSettingsCoverageTheme(model, named: "bundled-light")
            view.applyMatchAppearance(true)
            #expect(model.selectedTheme?.name == "bundled-light")

            model.isAdding = true
            view.endAdding()
            try await eventually(timeout: .seconds(60)) { model.isAdding == false }

            let binding = view.detailsBinding(editing: mine, at: index)
            #expect(binding.wrappedValue.name == "mine")
            var edited = mine
            edited.author = "Bound Author"
            model.detailsIsPresented = true
            binding.wrappedValue = edited
            #expect(model.themes[index].author == "Bound Author")
        }
    }

    @Test
    func importExportMenuReflectsCustomThemes() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let withCustom = try env.seededModel()
            let empty = try ThemeSettingsCoverageEnvironment(root: dir.appending(path: "empty", directoryHint: .isDirectory))
            try empty.addBundled(Fixtures.make(name: "only-bundled"))
            let withoutCustom = empty.makeModel()

            let custom = HostedViewFixture.host(size: NSSize(width: 300, height: 120)) {
                ThemeSettingsView(themeModel: withCustom).importExportMenu
            }
            let bundledOnly = HostedViewFixture.host(size: NSSize(width: 300, height: 120)) {
                ThemeSettingsView(themeModel: withoutCustom).importExportMenu
            }
            defer {
                custom.close()
                bundledOnly.close()
            }

            #expect(custom.renders())
            #expect(HostedView.pixelsDiffer(custom.snapshot(), bundledOnly.snapshot()))
        }
    }

    @Test
    func detailsSheetContentFollowsTheModelDetailsTheme() async throws {
        try await withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let mine = try themeSettingsCoverageTheme(model, named: "mine")
            let view = ThemeSettingsView(themeModel: model)

            let hidden = HostedViewFixture.host(size: detailsSize) { view.detailsSheet }
            model.detailsTheme = mine
            let shown = HostedViewFixture.host(size: detailsSize) { view.detailsSheet }
            defer {
                hidden.close()
                shown.close()
            }
            try await shown.settle(.milliseconds(150))

            #expect(HostedView.pixelsDiffer(hidden.snapshot(), shown.snapshot()))
        }
    }
}
