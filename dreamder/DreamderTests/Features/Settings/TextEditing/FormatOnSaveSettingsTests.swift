import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct FormatOnSaveSettingsTests {
    typealias Model = SettingsData.TextEditingSettings

    private static let hostSize = NSSize(width: 800, height: 1800)

    private func renderPage(formatOnSave: Bool) async throws -> NSBitmapImageRep? {
        let directory = try makeTemporaryDirectory(label: "FormatOnSaveSettingsTests")
        defer { removeTemporaryDirectory(directory) }
        let store = Settings(baseURL: directory)
        store.preferences.textEditing.formatOnSave = formatOnSave
        let host = HostedViewFixture.host(size: Self.hostSize) {
            SettingsInjector { TextEditingSettingsView() }.environment(\.settingsStore, store)
        }
        defer { host.close() }
        try await host.settle(.milliseconds(100))
        #expect(host.renders())
        return host.snapshot()
    }

    @Test
    func formatOnSaveIsOffByDefault() {
        #expect(Model().formatOnSave == false)
    }

    @Test
    func decodingJSONWithoutTheKeyKeepsItOff() throws {
        let empty = try JSONDecoder().decode(Model.self, from: Data("{}".utf8))
        let legacy = try JSONDecoder().decode(
            Model.self,
            from: Data(#"{"ensureFinalNewline":true,"stripTrailingSpaces":"allLines"}"#.utf8)
        )

        #expect(empty.formatOnSave == false)
        #expect(legacy.formatOnSave == false)
        #expect(legacy.ensureFinalNewline)
    }

    @Test
    func decodingTheKeyKeepsTheGivenValue() throws {
        let enabled = try JSONDecoder().decode(Model.self, from: Data(#"{"formatOnSave":true}"#.utf8))
        let disabled = try JSONDecoder().decode(Model.self, from: Data(#"{"formatOnSave":false}"#.utf8))

        #expect(enabled.formatOnSave)
        #expect(disabled.formatOnSave == false)
    }

    @Test
    func theFlagSurvivesAnEncodeDecodeRoundTrip() throws {
        var model = Model()
        model.formatOnSave = true

        let decoded = try JSONDecoder().decode(Model.self, from: JSONEncoder().encode(model))

        #expect(decoded.formatOnSave)
        #expect(decoded == model)
    }

    @Test
    func theSaveActionSettingsAreIndependentOfTheFlag() {
        var model = Model()
        let before = model.saveActionSettings
        model.formatOnSave = true

        #expect(model.saveActionSettings == before)
    }

    @Test
    func searchingFindsTheToggle() {
        #expect(Model().searchKeys.contains("Format on save"))
    }

    @Test
    func theActionsOnSaveSectionRendersTheToggleState() async throws {
        let off = try await renderPage(formatOnSave: false)
        let on = try await renderPage(formatOnSave: true)

        #expect(HostedView.pixelsDiffer(off, on))
    }
}
