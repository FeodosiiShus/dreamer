import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct AppearanceCommandsACoverageTests {
    private static let pathKey = Islands.BackgroundImageKey.path

    private func restoringBackgroundPath(_ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: Self.pathKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: Self.pathKey)
            } else {
                defaults.removeObject(forKey: Self.pathKey)
            }
        }
        try body()
    }

    @Test
    func chooseButtonAppliesThePickedImagePath() throws {
        try restoringBackgroundPath {
            let menu = CommandsACoverageSupport.host {
                AppearanceCommands.BackgroundImageButtons(chooseImage: { "/tmp/dreamder-appearance-picked.png" })
            }
            defer { menu.close() }

            #expect(menu.titles == ["Choose Background Image…", "Clear Background Image"])
            try menu.click(0)

            #expect(UserDefaults.standard.string(forKey: Self.pathKey) == "/tmp/dreamder-appearance-picked.png")
        }
    }

    @Test
    func cancelledPickerKeepsTheCurrentImagePath() throws {
        try restoringBackgroundPath {
            UserDefaults.standard.set("/tmp/dreamder-appearance-kept.png", forKey: Self.pathKey)
            let menu = CommandsACoverageSupport.host {
                AppearanceCommands.BackgroundImageButtons(chooseImage: { nil })
            }
            defer { menu.close() }

            try menu.click(0)

            #expect(UserDefaults.standard.string(forKey: Self.pathKey) == "/tmp/dreamder-appearance-kept.png")
        }
    }

    @Test
    func clearButtonEmptiesTheImagePath() throws {
        try restoringBackgroundPath {
            UserDefaults.standard.set("/tmp/dreamder-appearance-cleared.png", forKey: Self.pathKey)
            let menu = CommandsACoverageSupport.host {
                AppearanceCommands.BackgroundImageButtons(chooseImage: { nil })
            }
            defer { menu.close() }

            try menu.click(titled: "Clear Background Image")

            #expect(UserDefaults.standard.string(forKey: Self.pathKey) == "")
        }
    }

    @Test
    func defaultPickerOpensTheHeadlessOpenPanelAndCancels() throws {
        try restoringBackgroundPath {
            UserDefaults.standard.set("/tmp/dreamder-appearance-default.png", forKey: Self.pathKey)
            let menu = CommandsACoverageSupport.host {
                AppearanceCommands.BackgroundImageButtons()
            }
            defer { menu.close() }

            try menu.click(0)

            #expect(DreamderHeadless.suppressedModals.contains("Choose a background image"))
            #expect(UserDefaults.standard.string(forKey: Self.pathKey) == "/tmp/dreamder-appearance-default.png")
        }
    }

    @Test
    func commandBodyBuilds() {
        _ = AppearanceCommands().body
    }
}
