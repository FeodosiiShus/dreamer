import AppKit
import Testing
@testable import Dreamder

@MainActor
@Suite
struct IntelliJIconTests {
    @Test(arguments: [
        ("main.swift", "fileTypes/swiftLang"),
        ("App.TSX", "fileTypes/typeScript"),
        ("index.mjs", "fileTypes/javaScript"),
        ("package.json", "fileTypes/json"),
        ("README.md", "fileTypes/markdown"),
        ("Info.plist", "fileTypes/xml"),
        ("ci.yml", "fileTypes/yaml"),
        ("build.sh", "fileTypes/shell"),
        ("logo.SVG", "fileTypes/image"),
        ("notes.txt", "fileTypes/text"),
        (".gitignore", "fileTypes/gitignore"),
        ("Makefile", "fileTypes/anyType")
    ])
    func fileIconFollowsTheExtension(fileName: String, expected: String) {
        #expect(IntelliJIcon.fileIcon(for: fileName) == expected)
    }

    @Test(arguments: [
        "main.swift", "a.java", "a.class", "a.js", "a.ts", "a.json", "a.md", "a.html", "a.xhtml",
        "a.css", "a.xml", "a.yml", "a.sh", "a.png", "a.zip", "a.txt", ".gitignore", "unknown"
    ])
    func everyMappedIconExistsInTheAssetCatalog(fileName: String) {
        #expect(IntelliJIcon.nsImage(IntelliJIcon.fileIcon(for: fileName)) != nil)
    }
}
