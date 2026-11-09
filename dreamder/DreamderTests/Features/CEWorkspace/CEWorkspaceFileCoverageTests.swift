import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct CEWorkspaceFileCoverageTests {
    private func file(_ path: String) -> CEWorkspaceFile {
        CEWorkspaceFile(url: URL(fileURLWithPath: path))
    }

    private func label(
        _ path: String,
        _ visibility: SettingsData.FileExtensionsVisibility,
        shown: [String] = [],
        hidden: [String] = []
    ) -> String {
        var general = SettingsData.GeneralSettings()
        general.fileExtensionsVisibility = visibility
        general.shownFileExtensions = SettingsData.FileExtensions(extensions: shown)
        general.hiddenFileExtensions = SettingsData.FileExtensions(extensions: hidden)
        return file(path).labelFileName(general: general)
    }

    @Test
    func customSymbolIconsComeFromTheSymbolCatalogAndOthersFromSystemSymbols() {
        let json = file("/tmp/data.json")
        let swift = file("/tmp/App.swift")

        #expect(json.systemImage == "doc.json")
        #expect(json.nsIcon.accessibilityDescription != "doc.json")
        #expect(swift.nsIcon.accessibilityDescription == "swift")
    }

    @Test
    func swiftUIIconRendersForCustomAndSystemSymbols() {
        for path in ["/tmp/data.json", "/tmp/App.swift"] {
            let renderer = ImageRenderer(content: file(path).icon.frame(width: 16, height: 16))
            #expect(renderer.nsImage != nil)
        }
    }

    @Test
    func encodingWritesNameAndStatusAndDecodingRestoresThem() throws {
        let original = CEWorkspaceFile(
            id: "dir/b.txt",
            url: URL(fileURLWithPath: "/tmp/dir/b.txt"),
            changeType: .modified,
            staged: true
        )

        let data = try JSONEncoder().encode(original)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let decoded = try JSONDecoder().decode(CEWorkspaceFile.self, from: data)

        #expect(object["name"] as? String == "b.txt")
        #expect(decoded.id == "dir/b.txt")
        #expect(decoded.url == original.url)
        #expect(decoded.gitStatus == .modified)
        #expect(decoded.staged == true)
        #expect(decoded == original)
    }

    @Test
    func aFileWithoutGitStatusSurvivesARoundTrip() throws {
        let original = CEWorkspaceFile(url: URL(fileURLWithPath: "/tmp/plain.txt"))

        let decoded = try JSONDecoder().decode(CEWorkspaceFile.self, from: JSONEncoder().encode(original))

        #expect(decoded.url == original.url)
        #expect(decoded.gitStatus == nil)
        #expect(decoded.staged == false)
    }

    @Test
    func decodingRequiresIdentifierAndURL() {
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(CEWorkspaceFile.self, from: Data(#"{"id":"x"}"#.utf8))
        }
    }

    @Test
    func hideAllRemovesEveryExtension() {
        #expect(label("/tmp/App.swift", .hideAll) == "App")
        #expect(label("/tmp/Makefile", .hideAll) == "Makefile")
    }

    @Test
    func showAllKeepsEveryExtension() {
        #expect(label("/tmp/App.swift", .showAll) == "App.swift")
    }

    @Test
    func showOnlyKeepsTheListedExtensionsAndHidesTheRest() {
        #expect(label("/tmp/App.swift", .showOnly, shown: ["swift"]) == "App.swift")
        #expect(label("/tmp/notes.md", .showOnly, shown: ["swift"]) == "notes")
    }

    @Test
    func hideOnlyHidesTheListedExtensionsAndKeepsTheRest() {
        #expect(label("/tmp/App.swift", .hideOnly, hidden: ["swift"]) == "App")
        #expect(label("/tmp/notes.md", .hideOnly, hidden: ["swift"]) == "notes.md")
    }

    @Test
    func fileNameCanHideItsExtension() {
        let archive = file("/tmp/archive.tar.gz")

        #expect(archive.fileName() == "archive.tar.gz")
        #expect(archive.fileName(typeHidden: true) == "archive.tar")
    }

    @Test
    func filesOrderByTheirLastPathComponentRegardlessOfDirectory() {
        let early = file("/z/a.txt")
        let late = file("/a/b.txt")

        #expect(early < late)
        #expect(!(late < early))
        #expect(!(early < early))
    }

    @Test
    func nearestFolderIsTheFolderItselfOrTheParentFolderOfAFile() throws {
        try withTempDir { dir in
            let fileURL = dir.appending(path: "a.txt")
            try Data("x".utf8).write(to: fileURL)
            let expected = dir.path(percentEncoded: false)

            #expect(CEWorkspaceFile(url: dir).nearestFolder.path(percentEncoded: false) == expected)
            #expect(CEWorkspaceFile(url: fileURL).nearestFolder.path(percentEncoded: false) == expected)
        }
    }

    @Test
    func aMissingFolderCountsAsEmpty() throws {
        try withTempDir { dir in
            let missing = CEWorkspaceFile(url: dir.appending(path: "missing", directoryHint: .isDirectory))

            #expect(missing.isEmptyFolder)
            #expect(!missing.doesExist)
        }
    }
}
