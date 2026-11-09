import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Dreamder

extension CodeFileDocumentStateTests {
    @Test
    func documentWithoutAFileHasNoEditorConfig() {
        let document = CodeFileDocument()

        #expect(document.editorConfig == .empty)
        #expect(document.detectedIndent == nil)
        #expect(document.notice == nil)
        #expect(!document.isReadOnly)
    }

    @Test
    func readingDataIntoADocumentWithoutAFileLeavesTheEditorConfigEmpty() throws {
        let document = CodeFileDocument()

        try document.read(from: Data("a\n".utf8), ofType: "public.plain-text")

        #expect(document.content?.string == "a\n")
        #expect(document.fileURL == nil)
        #expect(document.editorConfig == .empty)
    }

    @Test
    func resolvedIndentFollowsThePrecedenceChain() throws {
        try withTempDir { dir in
            try writeRootConfig(in: dir, extra: "[*.py]\nindent_style = tab\ntab_width = 3\n")
            let configured = try makeDocument(in: dir, name: "a.py", text: "a:\n  b\n  c\n")
            let detected = try makeDocument(in: dir, name: "b.txt", text: "a:\n  b\n  c\n")
            let language = try makeDocument(in: dir, name: "main.go", text: "a\n")
            let global = try makeDocument(in: dir, name: "plain.txt", text: "a\n")

            #expect(configured.resolveIndent(global: Self.global) == ResolvedIndent(
                style: .tab, spaceCount: 3, tabWidth: 3, styleSource: .editorConfig
            ))
            #expect(detected.resolveIndent(global: Self.global) == ResolvedIndent(
                style: .spaces, spaceCount: 2, tabWidth: 4, styleSource: .detected
            ))
            #expect(language.resolveIndent(global: Self.global) == ResolvedIndent(
                style: .tab, spaceCount: 4, tabWidth: 4, styleSource: .languageDefault
            ))
            #expect(global.resolveIndent(global: Self.global) == ResolvedIndent(
                style: .spaces, spaceCount: 4, tabWidth: 4, styleSource: .global
            ))

            configured.indentOption = SettingsData.TextEditingSettings.IndentOption(indentType: .spaces, spaceCount: 7)
            configured.defaultTabWidth = 5
            #expect(configured.resolveIndent(global: Self.global) == ResolvedIndent(
                style: .spaces, spaceCount: 7, tabWidth: 5, styleSource: .documentOverride
            ))
        }
    }

    @Test
    func effectiveIndentReadsTheGlobalSettingAsTheLastResort() throws {
        try withTempDir { dir in
            try writeRootConfig(in: dir)
            let document = try makeDocument(in: dir, text: "a\n")
            let editing = Dreamder.Settings[\.textEditing]
            let global = CodeFileDocument.currentGlobalIndent()

            #expect(global.spaceCount == editing.indentOption.spaceCount)
            #expect(global.tabWidth == editing.defaultTabWidth)
            #expect(global.style == (editing.indentOption.indentType == .tab ? .tab : .spaces))
            #expect(document.effectiveTabWidth == editing.defaultTabWidth)
            #expect(document.effectiveIndentOption == editing.indentOption)
            #expect(document.resolvedIndent.styleSource == .global)
        }
    }

    @Test
    func effectiveIndentOptionMirrorsTheResolvedStyle() throws {
        try withTempDir { dir in
            try writeRootConfig(in: dir, extra: "[*]\nindent_style = tab\ntab_width = 6\n")
            let document = try makeDocument(in: dir, text: "a\n")

            #expect(document.effectiveIndentOption.indentType == .tab)
            #expect(document.effectiveTabWidth == 6)
        }
    }

    @Test
    func saveActionsRewriteTheBufferAndTheBytesWrittenToDisk() throws {
        try withTempDir { dir in
            try writeRootConfig(
                in: dir,
                extra: "[*.txt]\ninsert_final_newline = true\ntrim_trailing_whitespace = true\n"
            )
            let document = try makeDocument(in: dir, text: "a  \n\tb \nc")

            #expect(document.applySaveActions())
            #expect(document.content?.string == "a\n\tb\nc\n")
            #expect(!document.applySaveActions())

            let target = dir.appending(path: "out.txt")
            try document.write(to: target, ofType: "public.plain-text")
            #expect(try Data(contentsOf: target) == Data("a\n\tb\nc\n".utf8))
        }
    }

    @Test
    func saveActionsHonourTheConfiguredLineEndingForTheFinalNewline() throws {
        try withTempDir { dir in
            try writeRootConfig(in: dir, extra: "[*.txt]\ninsert_final_newline = true\nend_of_line = crlf\n")
            let document = try makeDocument(in: dir, text: "single line")

            #expect(document.applySaveActions())
            #expect(document.content?.string == "single line\r\n")
        }
    }

    @Test
    func saveActionsDoNothingWithoutConfiguration() throws {
        try withTempDir { dir in
            try writeRootConfig(in: dir)
            let document = try makeDocument(in: dir, text: "a  \nb")

            #expect(!document.applySaveActions())
            #expect(document.content?.string == "a  \nb")
        }
    }

    @Test
    func saveActionsDoNothingForADocumentWithoutContent() {
        #expect(!CodeFileDocument().applySaveActions())
    }

    @Test
    func savingWritesTheTransformedBytes() async throws {
        try await withTempDir { dir in
            try writeRootConfig(
                in: dir,
                extra: "[*.txt]\ninsert_final_newline = true\ntrim_trailing_whitespace = true\n"
            )
            let document = try makeDocument(in: dir, text: "a  \nb")
            let url = try #require(document.fileURL)
            document.updateChangeCount(.changeDone)

            document.save(withDelegate: nil, didSave: nil, contextInfo: nil)

            try await eventually { (try? Data(contentsOf: url)) == Data("a\nb\n".utf8) }
            #expect(document.content?.string == "a\nb\n")
        }
    }
}
