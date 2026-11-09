import AppKit
import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ThemeModelCoverageTests {
    private typealias Fixtures = ThemeSettingsCoverageThemes

    private func overrides(
        terminal: [String: String] = [:],
        editor: [String: String] = [:]
    ) -> SettingsData.ThemeOverrides {
        var result: SettingsData.ThemeOverrides = [:]
        if !terminal.isEmpty {
            result["terminal"] = terminal.mapValues { Theme.Attributes(color: $0) }
        }
        if !editor.isEmpty {
            result["editor"] = editor.mapValues { Theme.Attributes(color: $0) }
        }
        return result
    }

    @Test
    func defaultLocationsPointIntoApplicationSupportAndTheBundle() {
        #expect(ThemeModel.defaultBaseURL == Settings.defaultBaseURL())
        let bundled = ThemeModel.defaultBundledThemesURL
        #expect(bundled?.lastPathComponent == "DefaultThemes")
    }

    @Test
    func urlAccessorsDeriveFromTheInjectedBase() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = env.makeModel()

            #expect(model.themesURL == env.themesURL)
            #expect(model.extensionsURL == env.baseURL.appending(path: "Extensions", directoryHint: .isDirectory))
            #expect(model.settingsURL.lastPathComponent == "settings.json")
            #expect(model.bundledThemesURL == env.bundledURL)
            #expect(model.filemanager === FileManager.default)
        }
    }

    @Test
    func loadingCreatesTheThemesFolderAndReadsBundledThemes() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            try env.addBundled(Fixtures.make(name: "bundled-dark"))

            let model = env.makeModel()

            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: env.themesURL.path, isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
            #expect(model.themes.map(\.name) == ["bundled-dark"])
            #expect(model.themes.first?.isBundled == true)
        }
    }

    @Test
    func loadingMergesUserAndBundledThemesAndSkipsInvalidFiles() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            try env.addBundled(Fixtures.make(name: "bundled-dark"))
            try env.addBundled(Fixtures.make(name: "bundled-light", appearance: .light))
            let mineURL = try env.addUser(Fixtures.make(name: "mine"))
            try Data("{}".utf8).write(to: env.themesURL.appending(path: "broken.cetheme"))
            try Data("ignored".utf8).write(to: env.themesURL.appending(path: "notes.txt"))
            env.settings.preferences.theme.selectedDarkTheme = "bundled-dark"
            env.settings.preferences.theme.selectedLightTheme = "bundled-light"
            env.settings.preferences.theme.selectedTheme = "mine"

            let model = env.makeModel()

            #expect(Set(model.themes.map(\.name)) == ["bundled-dark", "bundled-light", "mine"])
            #expect(try themeSettingsCoverageTheme(model, named: "mine").isBundled == false)
            #expect(try themeSettingsCoverageTheme(model, named: "mine").fileURL == mineURL)
            #expect(try themeSettingsCoverageTheme(model, named: "bundled-dark").isBundled)
            #expect(model.darkThemes.count == 2)
            #expect(model.lightThemes.map(\.name) == ["bundled-light"])
            #expect(model.selectedDarkTheme?.name == "bundled-dark")
            #expect(model.selectedLightTheme?.name == "bundled-light")
            #expect(model.selectedTheme?.name == "mine")
            let activeMine = try themeSettingsCoverageTheme(model, named: "mine")
            let inactiveBundled = try themeSettingsCoverageTheme(model, named: "bundled-dark")
            #expect(model.getThemeActive(activeMine))
            #expect(model.getThemeActive(inactiveBundled) == false)
        }
    }

    @Test
    func unknownSelectedThemeFallsBackToTheDarkThemeInDarkAppearance() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            try env.addBundled(Fixtures.make(name: "bundled-dark"))
            try env.addBundled(Fixtures.make(name: "bundled-light", appearance: .light))
            env.settings.preferences.theme.selectedDarkTheme = "bundled-dark"
            env.settings.preferences.theme.selectedLightTheme = "bundled-light"
            env.settings.preferences.theme.selectedTheme = "missing"

            let model = try env.makeModel(appearance: .darkAqua)

            #expect(model.selectedTheme?.name == "bundled-dark")
        }
    }

    @Test
    func unknownSelectedThemeFallsBackToTheLightThemeInLightAppearance() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            try env.addBundled(Fixtures.make(name: "bundled-dark"))
            try env.addBundled(Fixtures.make(name: "bundled-light", appearance: .light))
            env.settings.preferences.theme.selectedDarkTheme = "bundled-dark"
            env.settings.preferences.theme.selectedLightTheme = "bundled-light"
            env.settings.preferences.theme.selectedTheme = "missing"

            let model = try env.makeModel(appearance: .aqua)

            #expect(model.selectedTheme?.name == "bundled-light")
        }
    }

    @Test
    func overridesFromSettingsAreAppliedWithoutTouchingTheFile() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let fileURL = try env.addUser(Fixtures.make(name: "mine"))
            env.settings.preferences.theme.overrides["mine"] = overrides(
                terminal: ["red": "#ff0000"],
                editor: ["keywords": "#00ff00", "unknown": "#0000ff"]
            )
            env.settings.preferences.theme.overrides["other"] = overrides(terminal: ["red": "#abcdef"])

            let model = env.makeModel(bundledThemesURL: env.bundledURL)

            let mine = try themeSettingsCoverageTheme(model, named: "mine")
            #expect(mine.terminal.red.color == "#ff0000")
            #expect(mine.terminal.green.color == "#112233")
            #expect(mine.editor.keywords.color == "#00ff00")
            #expect(mine.editor.types.color == "#112233")
            #expect(try Fixtures.decode(fileURL).terminal.red.color == "#112233")
        }
    }

    @Test
    func missingBundledFolderMakesLoadingThrowButInitSurvives() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let missing = env.root.appending(path: "missing", directoryHint: .isDirectory)

            let model = env.makeModel(bundledThemesURL: missing)

            #expect(model.themes.isEmpty)
            #expect(throws: Error.self) { try model.loadThemes() }
        }
    }

    @Test
    func unwritableThemesFolderMakesLoadingThrow() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            try Data("file".utf8).write(to: env.baseURL)

            let model = env.makeModel()

            #expect(model.themes.isEmpty)
            #expect(throws: Error.self) { try model.loadThemes() }
        }
    }

    @Test
    func withoutBundledFolderNothingIsLoaded() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            try env.addUser(Fixtures.make(name: "mine"))

            let model = env.makeModel(bundledThemesURL: nil)
            try model.loadThemes()

            #expect(model.themes.isEmpty)
            #expect(model.bundledThemesURL == nil)
        }
    }

    @Test
    func updateAppearanceThemeRecordsTheSelectedThemeForItsAppearance() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let dark = try themeSettingsCoverageTheme(model, named: "mine")
            let light = try themeSettingsCoverageTheme(model, named: "bundled-light")

            model.selectedDarkTheme = nil
            model.selectedLightTheme = nil
            model.selectedTheme = nil
            model.updateAppearanceTheme()
            #expect(model.selectedDarkTheme == nil)
            #expect(model.selectedLightTheme == nil)

            model.selectedTheme = dark
            model.updateAppearanceTheme()
            #expect(model.selectedDarkTheme?.name == "mine")
            #expect(model.selectedLightTheme == nil)

            model.selectedTheme = light
            model.updateAppearanceTheme()
            #expect(model.selectedLightTheme?.name == "bundled-light")
        }
    }

    @Test
    func selectionChangesArePersistedIntoTheSettingsStore() async throws {
        try await withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let light = try themeSettingsCoverageTheme(model, named: "bundled-light")
            let dark = try themeSettingsCoverageTheme(model, named: "bundled-dark")

            model.selectedLightTheme = light
            model.selectedDarkTheme = dark
            model.selectedTheme = light
            try await eventually {
                env.settings.preferences.theme.selectedLightTheme == "bundled-light"
                    && env.settings.preferences.theme.selectedDarkTheme == "bundled-dark"
                    && env.settings.preferences.theme.selectedTheme == "bundled-light"
            }

            model.selectedLightTheme = nil
            model.selectedDarkTheme = nil
            model.selectedTheme = nil
            try await eventually {
                env.settings.preferences.theme.selectedLightTheme == "Broken"
                    && env.settings.preferences.theme.selectedDarkTheme == "Broken"
                    && env.settings.preferences.theme.selectedTheme == nil
            }
        }
    }

    @Test
    func activatingAThemeUpdatesTheSlotOfTheCurrentColorScheme() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let light = try themeSettingsCoverageTheme(model, named: "bundled-light")
            let dark = try themeSettingsCoverageTheme(model, named: "bundled-dark")
            model.selectedLightTheme = nil
            model.selectedDarkTheme = nil

            model.colorScheme = .light
            model.activateTheme(light)
            #expect(model.selectedTheme?.name == "bundled-light")
            #expect(model.selectedLightTheme?.name == "bundled-light")
            #expect(model.selectedDarkTheme == nil)

            model.colorScheme = .dark
            model.activateTheme(dark)
            #expect(model.selectedTheme?.name == "bundled-dark")
            #expect(model.selectedDarkTheme?.name == "bundled-dark")
            #expect(model.selectedLightTheme?.name == "bundled-light")
        }
    }

    @Test
    func cancelDetailsRestoresAndSavesTheThemeBeingEdited() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            var mine = try themeSettingsCoverageTheme(model, named: "mine")
            let index = try #require(model.themes.firstIndex { $0.name == "mine" })
            let fileURL = try #require(mine.fileURL)

            model.cancelDetails(mine)
            #expect(model.themes[index].displayName == "Mine")

            mine.displayName = "Restored"
            model.detailsTheme = mine
            model.themes[index].displayName = "Edited"
            model.cancelDetails(model.themes[index])

            #expect(model.themes[index].displayName == "Restored")
            #expect(try Fixtures.decode(fileURL).displayName == "Restored")

            var stranger = mine
            stranger.fileURL = env.themesURL.appending(path: "stranger.cetheme")
            model.themes[index].displayName = "Untouched"
            model.cancelDetails(stranger)
            #expect(model.themes[index].displayName == "Untouched")
        }
    }

    @Test
    func exportWithoutFileURLDoesNothing() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let panels = FakeFilePanels()
            let model = try env.seededModel(filePanels: panels)

            model.exportTheme(Fixtures.make(name: "ghost"))

            #expect(panels.saveRequests.isEmpty)
        }
    }

    @Test
    func cancellingThePanelsChangesNothing() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let panels = FakeFilePanels()
            let model = try env.seededModel(filePanels: panels)
            let mine = try themeSettingsCoverageTheme(model, named: "mine")
            let count = model.themes.count

            model.exportTheme(mine)
            model.exportAllCustomThemes()
            model.importTheme()

            #expect(panels.saveRequests.count == 1)
            #expect(panels.openRequests.count == 2)
            #expect(model.themes.count == count)
            #expect(model.detailsIsPresented == false)
            #expect(try FileManager.default.contentsOfDirectory(atPath: env.outsideURL.path).isEmpty)
        }
    }

    @Test
    func exportCopiesTheThemeToTheChosenLocation() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let destination = env.outsideURL.appending(path: "exported.cetheme")
            let panels = FakeFilePanels(saveLocation: destination)
            let model = try env.seededModel(filePanels: panels)
            let mine = try themeSettingsCoverageTheme(model, named: "mine")

            model.exportTheme(mine)

            #expect(try Fixtures.decode(destination).name == "mine")
            let request = try #require(panels.saveRequests.first)
            #expect(request.prompt == "Export")
            #expect(request.nameFieldStringValue == mine.displayName)
            #expect(request.canCreateDirectories)
            #expect(request.allowedContentTypes == [UTType(filenameExtension: "cetheme") ?? .data])

            model.exportTheme(mine)
            #expect(try Fixtures.decode(destination).name == "mine")
        }
    }

    @Test
    func exportAllCopiesOnlyCustomThemesWithFiles() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let exportDirectory = env.root.appending(path: "export", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
            let panels = FakeFilePanels(files: [exportDirectory])
            let model = try env.seededModel(filePanels: panels)
            try env.addUser(Fixtures.make(name: "second", displayName: "Second"))
            try model.loadThemes()
            model.themes.append(Fixtures.make(name: "ghost", displayName: "Ghost"))

            model.exportAllCustomThemes()

            let exported = try FileManager.default.contentsOfDirectory(atPath: exportDirectory.path).sorted()
            #expect(exported == ["Mine.cetheme", "Second.cetheme"])
            let request = try #require(panels.openRequests.first)
            #expect(request.prompt == "Export")
            #expect(request.canChooseFiles == false)
            #expect(request.canChooseDirectories)
            #expect(request.allowsMultipleSelection == false)

            model.exportAllCustomThemes()
            #expect(try FileManager.default.contentsOfDirectory(atPath: exportDirectory.path).count == 2)
        }
    }

    @Test
    func importDuplicatesTheFirstChosenUrl() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let panels = FakeFilePanels()
            let model = try env.seededModel(filePanels: panels)
            let incoming = try env.addOutside(Fixtures.make(name: "imported", displayName: "Imported"))

            model.importTheme()
            #expect(model.themes.contains { $0.name == "imported" } == false)

            panels.chosenFiles = [incoming]
            model.importTheme()
            #expect(model.themes.contains { $0.name == "imported" })
            let request = try #require(panels.openRequests.first)
            #expect(request.prompt == "Import")
            #expect(request.allowedContentTypes == [UTType(filenameExtension: "cetheme") ?? .data])
            #expect(request.canChooseFiles)
            #expect(request.canChooseDirectories == false)
        }
    }

    @Test
    func duplicatingABundledThemeCreatesAnEditableCopy() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let bundled = try themeSettingsCoverageTheme(model, named: "bundled-dark")
            let previous = model.selectedTheme?.name

            model.duplicate(try #require(bundled.fileURL))

            let copyURL = env.themesURL.appending(path: "bundled-dark 1.cetheme")
            #expect(FileManager.default.fileExists(atPath: copyURL.path))
            let copy = try themeSettingsCoverageTheme(model, named: "bundled-dark-1")
            #expect(copy.displayName == "bundled-dark 1")
            #expect(copy.author == NSFullUserName())
            #expect(copy.isBundled == false)
            #expect(try Fixtures.decode(copyURL).name == "bundled-dark-1")
            #expect(try Fixtures.decode(copyURL).author == NSFullUserName())
            #expect(model.isAdding)
            #expect(model.previousTheme?.name == previous)
            #expect(model.selectedTheme?.name == "bundled-dark-1")
            #expect(model.detailsTheme?.name == "bundled-dark-1")
            #expect(model.detailsIsPresented)
        }
    }

    @Test
    func duplicatingACustomThemeNumbersTheCopiesAndStripsOldNumbers() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let mine = try themeSettingsCoverageTheme(model, named: "mine")

            model.duplicate(try #require(mine.fileURL))
            #expect(FileManager.default.fileExists(atPath: env.themesURL.appending(path: "mine 1.cetheme").path))
            let first = try themeSettingsCoverageTheme(model, named: "mine-1")

            model.duplicate(try #require(first.fileURL))
            #expect(FileManager.default.fileExists(atPath: env.themesURL.appending(path: "mine 2.cetheme").path))
            #expect(try themeSettingsCoverageTheme(model, named: "mine-2").displayName == "mine 2")
        }
    }

    @Test
    func importingAnExternalThemeKeepsItsMetadata() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let incoming = try env.addOutside(Fixtures.make(name: "imported", displayName: "Imported", author: "Ada"))

            model.duplicate(incoming)

            let imported = try themeSettingsCoverageTheme(model, named: "imported")
            #expect(imported.author == "Ada")
            #expect(imported.displayName == "imported")
            #expect(try Fixtures.decode(env.themesURL.appending(path: "imported.cetheme")).author == "Ada")
            #expect(model.selectedTheme?.name == "imported")
            #expect(model.detailsIsPresented)
        }
    }

    @Test
    func duplicatingAMissingFileLeavesTheModelUnchanged() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let count = model.themes.count

            model.duplicate(env.outsideURL.appending(path: "nope.cetheme"))

            #expect(model.themes.count == count)
            #expect(model.detailsIsPresented == false)
            #expect(model.isAdding)
        }
    }

    @Test
    func duplicatingAnInvalidThemeFileCopiesItButOpensNoDetails() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let invalid = env.outsideURL.appending(path: "invalid.cetheme")
            try Data("not json".utf8).write(to: invalid)
            let count = model.themes.count

            model.duplicate(invalid)

            #expect(FileManager.default.fileExists(atPath: env.themesURL.appending(path: "invalid.cetheme").path))
            #expect(model.themes.count == count)
            #expect(model.detailsIsPresented == false)
        }
    }

    @Test
    func duplicatingWithoutABundledFolderTreatsEveryFileAsBundled() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let incoming = try env.addOutside(Fixtures.make(name: "solo"))
            try FileManager.default.createDirectory(at: env.themesURL, withIntermediateDirectories: true)
            let model = env.makeModel(bundledThemesURL: nil)

            model.duplicate(incoming)

            #expect(FileManager.default.fileExists(atPath: env.themesURL.appending(path: "solo 1.cetheme").path))
            #expect(model.themes.isEmpty)
        }
    }

    @Test
    func duplicateSelectedThemeUsesTheSelectedFile() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()

            model.selectedTheme = nil
            model.duplicateSelectedTheme()
            #expect(model.detailsIsPresented == false)

            model.selectedTheme = Fixtures.make(name: "no-file")
            model.duplicateSelectedTheme()
            #expect(model.detailsIsPresented == false)

            model.selectedTheme = try themeSettingsCoverageTheme(model, named: "mine")
            model.duplicateSelectedTheme()
            #expect(FileManager.default.fileExists(atPath: env.themesURL.appending(path: "mine 1.cetheme").path))
            #expect(model.detailsIsPresented)
        }
    }

    @Test
    func renameMovesTheFileAndAvoidsDisplayNameClashes() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let mine = try themeSettingsCoverageTheme(model, named: "mine")

            model.rename(to: "Fresh", theme: mine)
            #expect(FileManager.default.fileExists(atPath: env.themesURL.appending(path: "Fresh.cetheme").path))
            #expect(FileManager.default.fileExists(atPath: env.themesURL.appending(path: "mine.cetheme").path) == false)
            #expect(model.themes.contains { $0.fileURL?.lastPathComponent == "Fresh.cetheme" })

            let fresh = try #require(model.themes.first { $0.fileURL?.lastPathComponent == "Fresh.cetheme" })
            model.rename(to: "Bundled Dark", theme: fresh)
            #expect(FileManager.default.fileExists(atPath: env.themesURL.appending(path: "Bundled Dark 1.cetheme").path))
        }
    }

    @Test
    func renameSkipsEveryTakenNumberedName() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            try env.addUser(Fixtures.make(name: "taken", displayName: "Taken"))
            try env.addUser(Fixtures.make(name: "taken-1", displayName: "Taken 1"))
            let model = try env.seededModel()
            let mine = try themeSettingsCoverageTheme(model, named: "mine")

            model.rename(to: "Taken", theme: mine)

            #expect(FileManager.default.fileExists(atPath: env.themesURL.appending(path: "Taken 2.cetheme").path))
        }
    }

    @Test
    func renameWithoutFileOrWithMissingFileDoesNothing() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let count = model.themes.count

            model.rename(to: "Anything", theme: Fixtures.make(name: "ghost"))
            var ghost = Fixtures.make(name: "ghost")
            ghost.fileURL = env.themesURL.appending(path: "ghost.cetheme")
            model.rename(to: "Anything", theme: ghost)

            #expect(model.themes.count == count)
        }
    }

    @Test
    func saveWritesPrettyJSONAndIgnoresThemesWithoutUsableFile() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            var mine = try themeSettingsCoverageTheme(model, named: "mine")
            let fileURL = try #require(mine.fileURL)

            mine.author = "Saved Author"
            model.save(mine)
            #expect(try Fixtures.decode(fileURL).author == "Saved Author")
            #expect(try String(contentsOf: fileURL, encoding: .utf8).contains("\n"))

            model.save(Fixtures.make(name: "no-file"))

            var broken = mine
            broken.fileURL = env.root.appending(path: "missing-folder/broken.cetheme")
            model.save(broken)
            #expect(FileManager.default.fileExists(atPath: env.root.appending(path: "missing-folder").path) == false)
        }
    }

    @Test
    func deleteRemovesTheFileTheOverridesAndReloads() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let mine = try themeSettingsCoverageTheme(model, named: "mine")
            env.settings.preferences.theme.overrides["mine"] = overrides(terminal: ["red": "#ff0000"])
            env.settings.preferences.theme.overrides["keep"] = overrides(terminal: ["red": "#ff0000"])

            model.delete(mine)

            #expect(FileManager.default.fileExists(atPath: env.themesURL.appending(path: "mine.cetheme").path) == false)
            #expect(model.themes.contains { $0.name == "mine" } == false)
            #expect(env.settings.preferences.theme.overrides["mine"] == nil)
            #expect(env.settings.preferences.theme.overrides["keep"] != nil)
        }
    }

    @Test
    func deleteIgnoresThemesWithoutFileAndSurvivesMissingFiles() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            env.settings.preferences.theme.overrides["ghost"] = overrides(terminal: ["red": "#ff0000"])
            let count = model.themes.count

            model.delete(Fixtures.make(name: "ghost"))
            var ghost = Fixtures.make(name: "ghost")
            ghost.fileURL = env.themesURL.appending(path: "ghost.cetheme")
            model.delete(ghost)

            #expect(model.themes.count == count)
            #expect(env.settings.preferences.theme.overrides["ghost"] != nil)
        }
    }

    @Test
    func matchAppearanceChangeSelectsTheThemeForTheScheme() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            model.selectedDarkTheme = try themeSettingsCoverageTheme(model, named: "bundled-dark")
            model.selectedLightTheme = try themeSettingsCoverageTheme(model, named: "bundled-light")

            model.matchAppearanceChanged(to: true, colorScheme: .dark)
            #expect(model.selectedTheme?.name == "bundled-dark")

            model.matchAppearanceChanged(to: true, colorScheme: .light)
            #expect(model.selectedTheme?.name == "bundled-light")

            env.settings.preferences.theme.selectedTheme = "mine"
            model.matchAppearanceChanged(to: false, colorScheme: .dark)
            #expect(model.selectedTheme?.name == "mine")

            env.settings.preferences.theme.selectedTheme = "missing"
            model.matchAppearanceChanged(to: false, colorScheme: .dark)
            #expect(model.selectedTheme == nil)
        }
    }

    @Test
    func showDetailsPresentsTheTheme() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let mine = try themeSettingsCoverageTheme(model, named: "mine")

            model.showDetails(of: mine)

            #expect(model.detailsTheme?.name == "mine")
            #expect(model.detailsIsPresented)
        }
    }

    @Test
    func commitDetailsStoresSavesAndReactivatesTheSelectedTheme() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let mine = try themeSettingsCoverageTheme(model, named: "mine")
            let index = try #require(model.themes.firstIndex { $0.name == "mine" })
            var edited = mine
            edited.author = "Edited Author"

            model.commitDetails(edited, at: index, editing: mine)
            #expect(model.themes[index].author == "Tester")

            model.detailsIsPresented = true
            env.settings.preferences.theme.selectedTheme = "other"
            model.commitDetails(edited, at: index, editing: mine)
            #expect(model.themes[index].author == "Edited Author")
            #expect(try Fixtures.decode(try #require(mine.fileURL)).author == "Edited Author")
            #expect(model.selectedTheme?.author != "Edited Author")

            env.settings.preferences.theme.selectedTheme = "mine"
            model.commitDetails(edited, at: index, editing: mine)
            #expect(model.selectedTheme?.author == "Edited Author")
        }
    }

    @Test
    func scheduleAddingResetClearsTheFlagAfterTheDelay() async throws {
        try await withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = env.makeModel(bundledThemesURL: nil)
            model.isAdding = true

            model.scheduleAddingReset(after: 0.01)

            #expect(model.isAdding)
            try await eventually { model.isAdding == false }
        }
    }

    @Test
    func beginDuplicatingReturnsTheThemeOnlyWhenItHasAFile() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let mine = try themeSettingsCoverageTheme(model, named: "mine")

            #expect(model.beginDuplicating(Fixtures.make(name: "no-file")) == nil)
            #expect(model.beginDuplicating(mine)?.name == "mine")
            #expect(FileManager.default.fileExists(atPath: env.themesURL.appending(path: "mine 1.cetheme").path))
        }
    }

    @Test
    func finishDetailsRenamesCustomThemesOnly() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            var mine = try themeSettingsCoverageTheme(model, named: "mine")
            let bundled = try themeSettingsCoverageTheme(model, named: "bundled-dark")

            model.finishDetails(bundled)
            #expect(FileManager.default.fileExists(atPath: env.bundledURL.appending(path: "bundled-dark.cetheme").path))
            #expect(model.themes.contains { $0.fileURL?.lastPathComponent == "bundled-dark.cetheme" })

            mine.displayName = "My Theme"
            model.finishDetails(mine)
            #expect(FileManager.default.fileExists(atPath: env.themesURL.appending(path: "My Theme.cetheme").path))
        }
    }

    @Test
    func cancellingWhileEditingRestoresTheDetailsAndDismisses() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let mine = try themeSettingsCoverageTheme(model, named: "mine")
            let index = try #require(model.themes.firstIndex { $0.name == "mine" })
            var original = mine
            original.displayName = "Original"
            model.detailsTheme = original
            model.themes[index].displayName = "Edited"

            #expect(model.cancelDetailsEditing(model.themes[index], duplicatingTheme: nil))
            #expect(model.themes[index].displayName == "Original")
        }
    }

    @Test
    func cancellingWhileEditingWithADuplicateKeepsTheSheetOpen() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let mine = try themeSettingsCoverageTheme(model, named: "mine")

            #expect(model.cancelDetailsEditing(mine, duplicatingTheme: mine) == false)
            #expect(model.isAdding == false)
        }
    }

    @Test
    func cancellingANewDuplicateDeletesItAndRestoresThePreviousTheme() async throws {
        try withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let mine = try themeSettingsCoverageTheme(model, named: "mine")
            let bundled = try themeSettingsCoverageTheme(model, named: "bundled-dark")
            model.duplicate(try #require(mine.fileURL))
            let copy = try themeSettingsCoverageTheme(model, named: "mine-1")
            let copyURL = try #require(copy.fileURL)
            model.previousTheme = bundled
            #expect(model.isAdding)

            let shouldDismiss = model.cancelDetailsEditing(copy, duplicatingTheme: mine)

            #expect(shouldDismiss == false)
            #expect(model.isAdding == false)
            #expect(model.detailsTheme?.name == "mine")
            #expect(FileManager.default.fileExists(atPath: copyURL.path) == false)
        }
    }

    @Test
    func cancellingANewThemeDeletesItAfterTheDelay() async throws {
        try await withTempDir { dir in
            let env = try ThemeSettingsCoverageEnvironment(root: dir)
            let model = try env.seededModel()
            let mine = try themeSettingsCoverageTheme(model, named: "mine")
            model.duplicate(try #require(mine.fileURL))
            let copy = try themeSettingsCoverageTheme(model, named: "mine-1")
            let copyURL = try #require(copy.fileURL)
            model.previousTheme = nil

            let shouldDismiss = model.cancelDetailsEditing(copy, duplicatingTheme: nil, deleteDelay: 0.01)

            #expect(shouldDismiss)
            #expect(model.isAdding)
            try await eventually { FileManager.default.fileExists(atPath: copyURL.path) == false }
        }
    }
}
