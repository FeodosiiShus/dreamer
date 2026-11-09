import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct CodeFileEditorConfigResolutionTests {
    private static let config = """
        root = true
        [*.txt]
        trim_trailing_whitespace = true
        insert_final_newline = true
        [*.md]
        trim_trailing_whitespace = false
        indent_style = tab
        tab_width = 8
        """

    private static let trimAllLines = SaveActionSettings(
        trailingSpaces: .allLines,
        keepTrailingSpacesOnCaretLine: false,
        ensureFinalNewline: false
    )

    private func makeDocument(in directory: URL, name: String = "notes.txt", text: String = "a  \n") throws
        -> CodeFileDocument {
        try Self.config.write(to: directory.appending(path: ".editorconfig"), atomically: true, encoding: .utf8)
        let url = directory.appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return try CodeFileDocument(for: url, withContentsOf: url, ofType: "public.plain-text")
    }

    @Test
    func theProductionInitializerResolvesTheEditorConfigOfTheOpenedFile() throws {
        try withTempDir { dir in
            try Self.config.write(to: dir.appending(path: ".editorconfig"), atomically: true, encoding: .utf8)
            let url = dir.appending(path: "notes.txt")
            try "a\n".write(to: url, atomically: true, encoding: .utf8)

            let document = try CodeFileDocument(contentsOf: url, ofType: "public.plain-text")
            defer { document.close() }

            #expect(document.editorConfig.trimTrailingWhitespace == true)
            #expect(document.editorConfig.insertFinalNewline == true)
        }
    }

    @Test
    func renamingTheFileResolvesTheEditorConfigOfTheNewName() throws {
        try withTempDir { dir in
            let document = try makeDocument(in: dir)
            defer { document.close() }
            #expect(document.editorConfig.trimTrailingWhitespace == true)
            #expect(document.editorConfig.indentStyle == nil)

            document.fileURL = dir.appending(path: "notes.md")

            #expect(document.editorConfig.trimTrailingWhitespace == false)
            #expect(document.editorConfig.indentStyle == .tab)
            #expect(document.editorConfig.tabWidth == 8)
            #expect(document.editorConfig.insertFinalNewline == nil)
        }
    }

    @Test
    func aRenamedDocumentKeepsTheTrailingSpacesItsNewSectionAllows() throws {
        try withTempDir { dir in
            let document = try makeDocument(in: dir)
            defer { document.close() }
            document.fileURL = dir.appending(path: "notes.md")

            #expect(!document.applySaveActions(settings: Self.trimAllLines))
            #expect(document.content?.string == "a  \n")
        }
    }

    @Test
    func aDocumentRenamedIntoATrimmingSectionTrimsOnSave() throws {
        try withTempDir { dir in
            let document = try makeDocument(in: dir, name: "notes.md")
            defer { document.close() }
            #expect(document.editorConfig.trimTrailingWhitespace == false)

            document.fileURL = dir.appending(path: "notes.txt")

            #expect(document.applySaveActions(settings: SaveActionSettings()))
            #expect(document.content?.string == "a\n")
        }
    }

    @Test
    func movingTheFileToAnotherFolderUsesThatFoldersEditorConfig() throws {
        try withTempDir { dir in
            let document = try makeDocument(in: dir)
            defer { document.close() }
            let other = dir.appending(path: "other")
            try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
            try "root = true\n[*.txt]\nindent_style = space\nindent_size = 7\n".write(
                to: other.appending(path: ".editorconfig"),
                atomically: true,
                encoding: .utf8
            )

            document.fileURL = other.appending(path: "notes.txt")

            #expect(
                document.editorConfig == EditorConfigProperties(
                    indentStyle: .space,
                    indentSize: 7,
                    tabWidth: 7
                )
            )
        }
    }

    @Test
    func clearingTheFileURLDropsTheEditorConfig() throws {
        try withTempDir { dir in
            let document = try makeDocument(in: dir)
            defer { document.close() }
            #expect(document.editorConfig != .empty)

            document.fileURL = nil

            #expect(document.editorConfig == .empty)
        }
    }

    @Test
    func reloadingTheContentResolvesTheEditorConfigAgain() throws {
        try withTempDir { dir in
            let document = try makeDocument(in: dir)
            defer { document.close() }
            try "root = true\n[*.txt]\ntrim_trailing_whitespace = false\n".write(
                to: dir.appending(path: ".editorconfig"),
                atomically: true,
                encoding: .utf8
            )

            document.reloadContentDiscardingEdits()

            #expect(document.editorConfig.trimTrailingWhitespace == false)
        }
    }

    @Test
    func settingTheFileURLOffTheMainThreadResolvesTheEditorConfigOnTheMainActor() async throws {
        try await withTempDir { dir in
            let document = try makeDocument(in: dir)
            defer { document.close() }
            let renamed = dir.appending(path: "notes.md")

            await Task.detached { document.fileURL = renamed }.value

            try await eventually(timeout: .seconds(20)) { document.editorConfig.trimTrailingWhitespace == false }
            #expect(document.editorConfig.indentStyle == .tab)
        }
    }
}
