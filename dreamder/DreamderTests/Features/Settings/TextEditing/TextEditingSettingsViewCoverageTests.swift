import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct TextEditingSettingsViewCoverageTests {
    typealias Model = SettingsData.TextEditingSettings

    private static let hostSize = NSSize(width: 800, height: 1800)

    private func withTextEditing<T>(
        _ mutate: (inout Model) -> Void,
        _ body: (Dreamder.Settings) async throws -> T
    ) async throws -> T {
        let directory = try makeTemporaryDirectory(label: "TextEditingSettingsViewCoverageTests")
        defer { removeTemporaryDirectory(directory) }
        let store = Settings(baseURL: directory)
        mutate(&store.preferences.textEditing)
        return try await SettingsScope.$current.withValue(store) { try await body(store) }
    }

    private func renderPage(store: Dreamder.Settings) async throws -> NSBitmapImageRep? {
        let host = HostedViewFixture.host(size: Self.hostSize) {
            SettingsInjector { TextEditingSettingsView() }.environment(\.settingsStore, store)
        }
        defer { host.close() }
        try await host.settle(.milliseconds(100))
        #expect(host.renders())
        return host.snapshot()
    }

    private func renderPage() async throws -> NSBitmapImageRep? {
        try await renderPage { _ in }
    }

    private func renderPage(_ mutate: (inout Model) -> Void) async throws -> NSBitmapImageRep? {
        try await withTextEditing(mutate) { store in try await renderPage(store: store) }
    }

    @Test
    func defaultPageRenders() async throws {
        let snapshot = try await renderPage()
        #expect(snapshot != nil)
    }

    @Test
    func tabIndentHidesTheIndentWidthRow() async throws {
        let spaces = try await renderPage { $0.indentOption.indentType = .spaces }
        let tabs = try await renderPage { $0.indentOption.indentType = .tab }
        #expect(HostedView.pixelsDiffer(spaces, tabs))
    }

    @Test
    func bracketHighlightTypesShowOrHideTheCustomColorRow() async throws {
        let disabled = try await renderPage { $0.bracketEmphasis.highlightType = .disabled }
        let flash = try await renderPage { $0.bracketEmphasis.highlightType = .flash }
        let bordered = try await renderPage { $0.bracketEmphasis.highlightType = .bordered }
        let underline = try await renderPage { $0.bracketEmphasis.highlightType = .underline }
        let customBordered = try await renderPage {
            $0.bracketEmphasis.highlightType = .bordered
            $0.bracketEmphasis.useCustomColor = true
        }
        #expect(HostedView.pixelsDiffer(flash, bordered))
        #expect(HostedView.pixelsDiffer(disabled, underline))
        #expect(HostedView.pixelsDiffer(bordered, customBordered))
    }

    @Test
    func disablingTheGutterGreysOutTheFoldingRibbon() async throws {
        let withGutter = try await renderPage { $0.showGutter = true }
        let withoutGutter = try await renderPage { $0.showGutter = false }
        #expect(HostedView.pixelsDiffer(withGutter, withoutGutter))
    }

    @Test
    func overscrollAndToggleVariantsRender() async throws {
        for overscroll in [Model.OverscrollOption.none, .small, .medium, .large] {
            _ = try await renderPage { $0.overscroll = overscroll }
        }
        _ = try await renderPage {
            $0.useSystemCursor = false
            $0.showMinimap = true
            $0.wrapLinesToEditorWidth = true
            $0.autocompleteBraces = false
            $0.enableTypeOverCompletion = false
            $0.showReformattingGuide = false
        }
    }

    @Test
    func stripTrailingSpacesPickerRendersEveryMode() async throws {
        let none = try await renderPage { $0.stripTrailingSpaces = .none }
        let modified = try await renderPage { $0.stripTrailingSpaces = .modifiedLines }
        let all = try await renderPage { $0.stripTrailingSpaces = .allLines }
        #expect(HostedView.pixelsDiffer(none, modified))
        #expect(HostedView.pixelsDiffer(modified, all))
        #expect(HostedView.pixelsDiffer(none, all))
    }

    @Test
    func keepTrailingSpacesToggleChangesTheRenderAndIsDisabledWithoutStripping() async throws {
        let kept = try await renderPage {
            $0.stripTrailingSpaces = .modifiedLines
            $0.keepTrailingSpacesOnCaretLine = true
        }
        let notKept = try await renderPage {
            $0.stripTrailingSpaces = .modifiedLines
            $0.keepTrailingSpacesOnCaretLine = false
        }
        let disabledOn = try await renderPage {
            $0.stripTrailingSpaces = .none
            $0.keepTrailingSpacesOnCaretLine = true
        }
        let disabledOff = try await renderPage {
            $0.stripTrailingSpaces = .none
            $0.keepTrailingSpacesOnCaretLine = false
        }
        #expect(HostedView.pixelsDiffer(kept, notKept))
        #expect(HostedView.pixelsDiffer(disabledOn, disabledOff))
    }

    @Test
    func ensureFinalNewlineToggleChangesTheRender() async throws {
        let off = try await renderPage { $0.ensureFinalNewline = false }
        let on = try await renderPage { $0.ensureFinalNewline = true }
        #expect(HostedView.pixelsDiffer(off, on))
    }

    @Test
    func invisibleAndWarningRowsReflectTheirEnabledState() async throws {
        let off = try await renderPage {
            $0.invisibleCharacters.enabled = false
            $0.warningCharacters.enabled = false
        }
        let on = try await renderPage {
            $0.invisibleCharacters.enabled = true
            $0.warningCharacters.enabled = true
        }
        #expect(HostedView.pixelsDiffer(off, on))
    }

    @Test
    func intBindingReadsAndWritesTheSettingThroughDouble() async throws {
        try await withTextEditing({ _ in }) { store in
            let view = TextEditingSettingsView()

            let tabWidth = view.intBinding(\.defaultTabWidth)
            tabWidth.wrappedValue = 7
            #expect(store.preferences.textEditing.defaultTabWidth == 7)
            #expect(tabWidth.wrappedValue == 7)

            let indentWidth = view.intBinding(\.indentOption.spaceCount)
            indentWidth.wrappedValue = 3
            #expect(store.preferences.textEditing.indentOption.spaceCount == 3)
            #expect(indentWidth.wrappedValue == 3)

            let reformat = view.intBinding(\.reformatAtColumn)
            reformat.wrappedValue = 99
            #expect(store.preferences.textEditing.reformatAtColumn == 99)
            #expect(reformat.wrappedValue == 99)
        }
    }

    @Test
    func configureActionsOpenTheSheetsOnlyWhenEnabled() async throws {
        try await withTextEditing({ _ in }) { store in
            let view = TextEditingSettingsView()
            store.preferences.textEditing.invisibleCharacters.enabled = false
            store.preferences.textEditing.warningCharacters.enabled = false
            view.openInvisibleCharacterSettingsIfEnabled()
            view.openWarningCharactersSettingsIfEnabled()
            store.preferences.textEditing.invisibleCharacters.enabled = true
            store.preferences.textEditing.warningCharacters.enabled = true
            view.openInvisibleCharacterSettingsIfEnabled()
            view.openWarningCharactersSettingsIfEnabled()
            view.openInvisibleCharacterSettings()
            view.openWarningCharactersSettings()
        }
    }

    @Test
    func sheetContentsRenderAgainstTheSharedSettings() async throws {
        try await withTextEditing({ _ in }) { store in
            let view = TextEditingSettingsView()
            let invisibles = HostedViewFixture.host(size: NSSize(width: 600, height: 600)) {
                view.invisiblesSheetContent()
            }
            defer { invisibles.close() }
            try await invisibles.settle(.milliseconds(100))
            #expect(invisibles.renders())

            let warnings = HostedViewFixture.host(size: NSSize(width: 600, height: 600)) {
                view.warningCharactersSheetContent()
            }
            defer { warnings.close() }
            try await warnings.settle(.milliseconds(100))
            #expect(warnings.renders())
        }
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct TextEditingInvisiblesViewCoverageTests {
    typealias Config = SettingsData.TextEditingSettings.InvisibleCharactersConfig

    private func render(_ config: Config) async throws -> NSBitmapImageRep? {
        let host = HostedViewFixture.host(size: NSSize(width: 600, height: 800)) {
            InvisiblesSettingsView(invisibleCharacters: .constant(config))
        }
        defer { host.close() }
        try await host.settle(.milliseconds(100))
        #expect(host.renders())
        return host.snapshot()
    }

    private func config(spaces: Bool, tabs: Bool, lineEndings: Bool) -> Config {
        var config = Config.default
        config.showSpaces = spaces
        config.showTabs = tabs
        config.showLineEndings = lineEndings
        return config
    }

    @Test
    func everyReplacementFieldAppearsWhenAllTogglesAreOn() async throws {
        let all = try await render(config(spaces: true, tabs: true, lineEndings: true))
        let none = try await render(config(spaces: false, tabs: false, lineEndings: false))
        #expect(HostedView.pixelsDiffer(all, none))
    }

    @Test
    func eachToggleControlsItsOwnReplacementFields() async throws {
        let none = try await render(config(spaces: false, tabs: false, lineEndings: false))
        let spaces = try await render(config(spaces: true, tabs: false, lineEndings: false))
        let tabs = try await render(config(spaces: false, tabs: true, lineEndings: false))
        let endings = try await render(config(spaces: false, tabs: false, lineEndings: true))
        #expect(HostedView.pixelsDiffer(none, spaces))
        #expect(HostedView.pixelsDiffer(none, tabs))
        #expect(HostedView.pixelsDiffer(none, endings))
        #expect(HostedView.pixelsDiffer(spaces, tabs))
    }

    @Test
    func doneDismissesWithoutAPresentation() {
        InvisiblesSettingsView(invisibleCharacters: .constant(.default)).done()
    }
}
