import Foundation
import Testing
@testable import Dreamder

private final class RefusingMoveFileManager: FileManager {
    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        throw CocoaError(.fileWriteNoPermission)
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct SettingsCorruptFileTests {
    private static let preservedPrefix = "settings.json.invalid-"

    private func settingsFile(in directory: URL) -> URL {
        directory.appending(path: "settings.json")
    }

    private func write(_ text: String, in directory: URL) throws {
        try Data(text.utf8).write(to: settingsFile(in: directory))
    }

    private func preservedFiles(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
            .filter { $0.hasPrefix(Self.preservedPrefix) }
            .sorted()
            .map { directory.appending(path: $0) }
    }

    private func savedPreferences(in directory: URL) throws -> SettingsData {
        try JSONDecoder().decode(SettingsData.self, from: Data(contentsOf: settingsFile(in: directory)))
    }

    private func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    @Test
    func oneWrongTypedKeyKeepsTheOtherSettingsAndTheFileSurvivesTheNextSave() throws {
        try withTempDir { directory in
            try write(#"{"general":{"isAutoSaveOn":false},"textEditing":{"defaultTabWidth":"2"}}"#, in: directory)
            let settings = Settings(baseURL: directory, clock: TestClock())

            #expect(settings.preferences.general.isAutoSaveOn == false)
            #expect(settings.preferences.textEditing.defaultTabWidth == 4)

            settings.preferences.theme.useThemeBackground = false
            settings.flushPendingSave()

            let saved = try savedPreferences(in: directory)
            #expect(saved.general.isAutoSaveOn == false)
            #expect(saved.theme.useThemeBackground == false)
            #expect(try preservedFiles(in: directory).isEmpty)
        }
    }

    @Test
    func aMissingFileIsCreatedWithoutPreservingAnything() throws {
        try withTempDir { directory in
            let base = directory.appending(path: "fresh", directoryHint: .isDirectory)

            let settings = Settings(baseURL: base, clock: TestClock())

            #expect(settings.preferences == SettingsData())
            #expect(fileExists(base))
            #expect(!fileExists(settingsFile(in: base)))
            let preserved = try preservedFiles(in: base)
            #expect(preserved.isEmpty)
        }
    }

    @Test(arguments: ["not json", "", "{", #"{"general":"#, "[1, 2]", "5", "null"])
    func anUnparseableFileIsPreservedBeforeAnythingIsWritten(original: String) throws {
        try withTempDir { directory in
            try write(original, in: directory)

            let settings = Settings(baseURL: directory, clock: TestClock())

            #expect(settings.preferences == SettingsData())
            #expect(!fileExists(settingsFile(in: directory)))
            let preserved = try #require(try preservedFiles(in: directory).first)
            #expect(try String(contentsOf: preserved, encoding: .utf8) == original)
            #expect(try preservedFiles(in: directory).count == 1)

            settings.preferences.general.isAutoSaveOn = false
            settings.flushPendingSave()

            #expect(try savedPreferences(in: directory).general.isAutoSaveOn == false)
            #expect(try String(contentsOf: preserved, encoding: .utf8) == original)
        }
    }

    @Test
    func aFileThatCannotBeReadIsPreservedToo() throws {
        try withTempDir { directory in
            let file = settingsFile(in: directory)
            try write("not json", in: directory)
            let path = file.path(percentEncoded: false)
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: path)

            let settings = Settings(baseURL: directory, clock: TestClock())

            #expect(settings.preferences == SettingsData())
            #expect(!fileExists(file))
            #expect(try preservedFiles(in: directory).count == 1)
        }
    }

    @Test
    func everyUnreadableFileGetsItsOwnPreservedCopy() throws {
        try withTempDir { directory in
            try write("first broken file", in: directory)
            _ = Settings(baseURL: directory, clock: TestClock())
            try write("second broken file", in: directory)
            _ = Settings(baseURL: directory, clock: TestClock())

            let contents = try preservedFiles(in: directory)
                .map { try String(contentsOf: $0, encoding: .utf8) }
                .sorted()

            #expect(contents == ["first broken file", "second broken file"])
        }
    }

    @Test
    func whenPreservingFailsTheUnreadableFileIsNeverOverwritten() throws {
        try withTempDir { directory in
            try write("not json", in: directory)
            let settings = Settings(baseURL: directory, clock: TestClock(), fileManager: RefusingMoveFileManager())

            settings.preferences.general.isAutoSaveOn = false
            settings.flushPendingSave()

            #expect(settings.preferences.general.isAutoSaveOn == false)
            #expect(try String(contentsOf: settingsFile(in: directory), encoding: .utf8) == "not json")
            #expect(try preservedFiles(in: directory).isEmpty)
        }
    }
}
