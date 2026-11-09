import AppKit
import Foundation
import LanguageServerProtocol
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct InlayHintSettingsTests {
    typealias Model = SettingsData.TextEditingSettings

    @Test
    func defaultsFollowIntelliJ() {
        let settings = InlayHintSettings()
        #expect(settings.enabled)
        #expect(settings.parameterNames == .literals)
        #expect(settings.types)
        #expect(settings.returnTypes)
        #expect(Model().inlayHints == settings)
        #expect(InlayHintSettings.ParameterNameHints.allCases == [.none, .literals, .all])
    }

    @Test
    func everyFieldSurvivesARoundTrip() throws {
        var model = Model()
        model.inlayHints.enabled = false
        model.inlayHints.parameterNames = .all
        model.inlayHints.types = false
        model.inlayHints.returnTypes = false
        let decoded = try JSONDecoder().decode(Model.self, from: JSONEncoder().encode(model))
        #expect(decoded == model)
        #expect(decoded.inlayHints.parameterNames == .all)
    }

    @Test
    func legacySettingsWithoutTheGroupDecodeToDefaults() throws {
        let legacy = try JSONDecoder().decode(Model.self, from: Data(#"{"defaultTabWidth": 2}"#.utf8))
        #expect(legacy.inlayHints == InlayHintSettings())
        let partial = try JSONDecoder().decode(Model.self, from: Data(#"{"inlayHints": {"types": false}}"#.utf8))
        #expect(partial.inlayHints.enabled)
        #expect(partial.inlayHints.parameterNames == .literals)
        #expect(!partial.inlayHints.types)
        #expect(partial.inlayHints.returnTypes)
        let named = try JSONDecoder().decode(
            InlayHintSettings.self,
            from: Data(#"{"parameterNames": "none", "enabled": false, "returnTypes": false}"#.utf8)
        )
        #expect(named.parameterNames == .none)
        #expect(!named.enabled)
        #expect(!named.returnTypes)
    }

    @Test
    func searchKeysListTheInlayHintRows() {
        let keys = Model().searchKeys
        for key in ["Inlay hints", "Show inlay hints", "Parameter name hints", "Type hints", "Return type hints"] {
            #expect(keys.contains(NSLocalizedString(key, comment: "")))
        }
    }

    @Test
    func kindFilteringHonoursEveryToggle() {
        var settings = InlayHintSettings()
        #expect(settings.shows(kind: .parameter, followsClosingParenthesis: false))
        #expect(settings.shows(kind: .type, followsClosingParenthesis: false))
        #expect(settings.shows(kind: .type, followsClosingParenthesis: true))
        #expect(settings.shows(kind: nil, followsClosingParenthesis: false))

        settings.types = false
        #expect(!settings.shows(kind: .type, followsClosingParenthesis: false))
        #expect(settings.shows(kind: .type, followsClosingParenthesis: true))
        settings.types = true
        settings.returnTypes = false
        #expect(settings.shows(kind: .type, followsClosingParenthesis: false))
        #expect(!settings.shows(kind: .type, followsClosingParenthesis: true))
        settings.parameterNames = .none
        #expect(!settings.shows(kind: .parameter, followsClosingParenthesis: false))
        settings.parameterNames = .all
        #expect(settings.shows(kind: .parameter, followsClosingParenthesis: false))
        settings.enabled = false
        #expect(!settings.shows(kind: .parameter, followsClosingParenthesis: false))
        #expect(!settings.shows(kind: nil, followsClosingParenthesis: false))
    }

    @Test
    func typeScriptPreferencesPayloadMirrorsTheSettings() {
        var settings = InlayHintSettings()
        #expect(InlayHintServerPreferences.preferences(for: settings) == .hash([
            "includeInlayParameterNameHints": .string("literals"),
            "includeInlayVariableTypeHints": .bool(true),
            "includeInlayPropertyDeclarationTypeHints": .bool(true),
            "includeInlayFunctionLikeReturnTypeHints": .bool(true)
        ]))

        settings.parameterNames = .all
        settings.types = false
        settings.returnTypes = false
        #expect(InlayHintServerPreferences.preferences(for: settings) == .hash([
            "includeInlayParameterNameHints": .string("all"),
            "includeInlayVariableTypeHints": .bool(false),
            "includeInlayPropertyDeclarationTypeHints": .bool(false),
            "includeInlayFunctionLikeReturnTypeHints": .bool(false)
        ]))

        settings.enabled = false
        settings.types = true
        settings.returnTypes = true
        #expect(InlayHintServerPreferences.preferences(for: settings) == .hash([
            "includeInlayParameterNameHints": .string("none"),
            "includeInlayVariableTypeHints": .bool(false),
            "includeInlayPropertyDeclarationTypeHints": .bool(false),
            "includeInlayFunctionLikeReturnTypeHints": .bool(false)
        ]))
    }

    @Test
    func initializationOptionsAndConfigurationWrapThePreferences() {
        let settings = InlayHintSettings()
        let preferences = InlayHintServerPreferences.preferences(for: settings)
        #expect(InlayHintServerPreferences.initializationOptions(for: settings) == .hash(["preferences": preferences]))
        let section = LSPAny.hash(["inlayHints": preferences])
        #expect(
            InlayHintServerPreferences.configurationSettings(for: settings)
                == .hash(["typescript": section, "javascript": section])
        )
    }

    @Test
    func coverageClassifiesAndShiftsEdits() {
        let coverage = InlayHintCoverage(range: NSRange(location: 100, length: 50))
        #expect(coverage.relation(toEdit: NSRange(location: 10, length: 5)) == .before)
        #expect(coverage.relation(toEdit: NSRange(location: 95, length: 5)) == .overlapping)
        #expect(coverage.relation(toEdit: NSRange(location: 100, length: 0)) == .overlapping)
        #expect(coverage.relation(toEdit: NSRange(location: 150, length: 0)) == .overlapping)
        #expect(coverage.relation(toEdit: NSRange(location: 151, length: 0)) == .after)
        #expect(coverage.shifted(by: 7).range == NSRange(location: 107, length: 50))
        #expect(coverage.shifted(by: -500).range == NSRange(location: 0, length: 50))
        #expect(coverage.contains(NSRange(location: 100, length: 50)))
        #expect(!coverage.contains(NSRange(location: 99, length: 10)))
        #expect(!coverage.contains(NSRange(location: 120, length: 40)))
    }

    private func render(_ mutate: (inout InlayHintSettings) -> Void) async throws -> NSBitmapImageRep? {
        let directory = try makeTemporaryDirectory(label: "InlayHintSettingsTests")
        defer { removeTemporaryDirectory(directory) }
        let store = Settings(baseURL: directory)
        mutate(&store.preferences.textEditing.inlayHints)
        let host = HostedViewFixture.host(size: NSSize(width: 800, height: 1800)) {
            SettingsInjector { TextEditingSettingsView() }.environment(\.settingsStore, store)
        }
        defer { host.close() }
        try await host.settle(.milliseconds(100))
        #expect(host.renders())
        return host.snapshot()
    }

    @Test
    func settingsPageRendersTheInlayHintsSectionAndDisablesDependentRows() async throws {
        let enabled = try await render { _ in }
        let disabled = try await render { $0.enabled = false }
        let none = try await render { $0.parameterNames = .none }
        let all = try await render { $0.parameterNames = .all }
        let noTypes = try await render {
            $0.types = false
            $0.returnTypes = false
        }
        #expect(HostedView.pixelsDiffer(enabled, disabled))
        #expect(HostedView.pixelsDiffer(none, all))
        #expect(HostedView.pixelsDiffer(enabled, noTypes))
    }

    @Test
    func toggleMenuItemRendersAndFlipsTheSettingThroughItsBinding() async throws {
        let directory = try makeTemporaryDirectory(label: "InlayHintSettingsTests")
        defer { removeTemporaryDirectory(directory) }
        let store = Settings(baseURL: directory)
        store.preferences.textEditing.inlayHints.enabled = true
        let button = InlayHintCommands.ToggleInlayHintsButton()
        let menu = CommandsACoverageSupport.host {
            InlayHintCommands.ToggleInlayHintsButton().environment(\.settingsStore, store)
        }
        defer { menu.close() }
        #expect(menu.items.count == 1)
        SettingsScope.$current.withValue(store) {
            button.enabled.toggle()
            #expect(!store.preferences.textEditing.inlayHints.enabled)
            button.$enabled.wrappedValue = true
            #expect(store.preferences.textEditing.inlayHints.enabled)
        }
        _ = InlayHintCommands().body
    }
}
