import SwiftUI
import Testing
@testable import Dreamder

@Suite
struct CEWorkspaceFileIconTests {
    static let iconNames: [(FileIcon.FileType, String)] = [
        (.swift, "swift"),
        (.json, "doc.json"),
        (.yml, "doc.json"),
        (.resolved, "doc.json"),
        (.md, "doc.plaintext"),
        (.txt, "doc.plaintext"),
        (.png, "photo"),
        (.pdf, "photo"),
        (.js, "doc.javascript"),
        (.tsx, "atom"),
        (.Makefile, "terminal"),
        (.sh, "terminal"),
        (.mod, "m.square"),
        (.m, "m.square"),
        (.sum, "s.square"),
        (.kt, "doc.plaintext"),
        (.mp4, "film"),
        (.wav, "speaker.wave.2"),
        (.LICENSE, "key.fill"),
        (.gitignore, "arrow.triangle.branch"),
        (.lock, "lock.doc"),
        (.css, "curlybraces"),
        (.env, "gearshape.fill"),
        (.example, "gearshape.fill"),
        (.jpeg, "photo"),
        (.ico, "photo"),
        (.svg, "square.fill.on.circle.fill"),
        (.entitlements, "checkmark.seal"),
        (.plist, "tablecells"),
        (.rtf, "doc.richtext"),
        (.html, "chevron.left.forwardslash.chevron.right"),
        (.java, "cup.and.saucer"),
        (.py, "doc.python"),
        (.rb, "doc.ruby"),
        (.strings, "text.quote"),
        (.h, "h.square"),
        (.vue, "v.square"),
        (.go, "g.square"),
        (.rs, "r.square"),
        (.scpt, "applescript"),
        (.xcconfig, "gearshape.2"),
        (.cetheme, "paintbrush"),
        (.mjs, "doc.javascript"),
        (.jsx, "atom"),
        (.bash, "terminal"),
        (.mp3, "speaker.wave.2"),
        (.avi, "film")
    ]

    static let fileNames: [(String, FileIcon.FileType)] = [
        ("Package.swift", .swift),
        ("index.ts", .ts),
        ("Package.resolved", .resolved),
        ("README.md", .md),
        ("logo.png", .png),
        ("ci.yml", .yml),
        ("data.json", .json),
        ("Makefile", .Makefile),
        ("LICENSE", .LICENSE),
        (".gitignore", .gitignore),
        (".env", .env),
        ("app.test.ts", .ts),
        ("archive.swift.bak", .swift),
        ("a.ts.swift", .swift),
        ("notes.unknownext", .txt),
        ("unknown", .txt),
        ("UPPER.SWIFT", .txt),
        ("makefile", .txt)
    ]

    @Test(arguments: iconNames)
    func iconNamePerFileType(fileType: FileIcon.FileType, expected: String) {
        #expect(FileIcon.fileIcon(fileType: fileType) == expected)
    }

    @Test
    func fileTypesWithoutDedicatedSymbolUseGenericDocument() {
        #expect(FileIcon.fileIcon(fileType: .ts) == "doc")
        #expect(FileIcon.fileIcon(fileType: .c) == "doc")
        #expect(FileIcon.fileIcon(fileType: .zsh) == "terminal")
        #expect(FileIcon.fileIcon(fileType: nil) == "doc")
    }

    @Test
    func fileTypeRawValuesMatchNamesUsedForLookup() {
        #expect(FileIcon.FileType(rawValue: "Makefile") == .Makefile)
        #expect(FileIcon.FileType(rawValue: "LICENSE") == .LICENSE)
        #expect(FileIcon.FileType(rawValue: "text") == .txt)
        #expect(FileIcon.FileType(rawValue: "txt") == nil)
        #expect(FileIcon.FileType(rawValue: "SWIFT") == nil)
    }
}

@MainActor
@Suite(.uiGate)
struct CEWorkspaceFileColorAndWorkspaceFileTests {
    private static let goTeal = Color(red: 0.02, green: 0.675, blue: 0.757, opacity: 1.0)
    private static let makefileRed = Color(red: 0.937, green: 0.325, blue: 0.314, opacity: 1.0)
    private static let vueGreen = Color(red: 0.255, green: 0.722, blue: 0.514, opacity: 1.0)
    private static let headerRed = Color(red: 0.667, green: 0.031, blue: 0.133, opacity: 1.0)
    private static let objectiveCPurple = Color(red: 0.271, green: 0.106, blue: 0.525, opacity: 1.0)
    private static let modulePink = Color(red: 0.925, green: 0.251, blue: 0.478, opacity: 1.0)

    @Test
    func iconColorPerFileType() {
        #expect(FileIcon.iconColor(fileType: .swift) == .orange)
        #expect(FileIcon.iconColor(fileType: .html) == .orange)
        #expect(FileIcon.iconColor(fileType: .rs) == .orange)
        #expect(FileIcon.iconColor(fileType: .ts) == .blue)
        #expect(FileIcon.iconColor(fileType: .png) == .blue)
        #expect(FileIcon.iconColor(fileType: .css) == .teal)
        #expect(FileIcon.iconColor(fileType: .jsx) == .cyan)
        #expect(FileIcon.iconColor(fileType: .tsx) == .cyan)
        #expect(FileIcon.iconColor(fileType: .c) == .purple)
        #expect(FileIcon.iconColor(fileType: .js) == Color.amber)
        #expect(FileIcon.iconColor(fileType: .py) == Color.amber)
        #expect(FileIcon.iconColor(fileType: .json) == Color.scarlet)
        #expect(FileIcon.iconColor(fileType: .yml) == Color.scarlet)
        #expect(FileIcon.iconColor(fileType: .sh) == Color.steel)
        #expect(FileIcon.iconColor(fileType: .go) == Self.goTeal)
        #expect(FileIcon.iconColor(fileType: .Makefile) == Self.makefileRed)
        #expect(FileIcon.iconColor(fileType: .vue) == Self.vueGreen)
        #expect(FileIcon.iconColor(fileType: .h) == Self.headerRed)
        #expect(FileIcon.iconColor(fileType: .m) == Self.objectiveCPurple)
        #expect(FileIcon.iconColor(fileType: .sum) == Self.modulePink)
        #expect(FileIcon.iconColor(fileType: .mod) == Self.modulePink)
        #expect(FileIcon.iconColor(fileType: .java) == .blue)
        #expect(FileIcon.iconColor(fileType: .jpg) == .blue)
        #expect(FileIcon.iconColor(fileType: .svg) == .blue)
        #expect(FileIcon.iconColor(fileType: .mjs) == Color.amber)
        #expect(FileIcon.iconColor(fileType: .entitlements) == Color.amber)
        #expect(FileIcon.iconColor(fileType: .LICENSE) == Color.amber)
        #expect(FileIcon.iconColor(fileType: .resolved) == Color.scarlet)
        #expect(FileIcon.iconColor(fileType: .rb) == Color.scarlet)
        #expect(FileIcon.iconColor(fileType: .strings) == Color.scarlet)
        #expect(FileIcon.iconColor(fileType: .plist) == Color.steel)
        #expect(FileIcon.iconColor(fileType: .xcconfig) == Color.steel)
        #expect(FileIcon.iconColor(fileType: .cetheme) == .purple)
    }

    @Test
    func unknownOrMissingTypeFallsBackToSteel() {
        #expect(FileIcon.iconColor(fileType: nil) == Color.steel)
        #expect(FileIcon.iconColor(fileType: .md) == Color.steel)
        #expect(FileIcon.iconColor(fileType: .txt) == Color.steel)
    }

    @Test(arguments: CEWorkspaceFileIconTests.fileNames)
    func workspaceFileTypeFromName(name: String, expected: FileIcon.FileType) {
        let file = CEWorkspaceFile(url: URL(fileURLWithPath: "/tmp/\(name)"))
        #expect(file.type == expected)
    }

    @Test
    func extensionlessNameMatchesFileTypeDirectly() {
        let file = CEWorkspaceFile(url: URL(fileURLWithPath: "/tmp/swift"))
        #expect(file.type == .swift)
    }

    @Test
    func lastKnownExtensionWinsOverEarlierOnes() {
        let file = CEWorkspaceFile(url: URL(fileURLWithPath: "/tmp/mod.sum"))
        #expect(file.type == .sum)
        let multi = CEWorkspaceFile(url: URL(fileURLWithPath: "/tmp/build.mod.go.zzz"))
        #expect(multi.type == .go)
    }

    @Test
    func workspaceFileIconAndColorFollowResolvedType() {
        let swiftFile = CEWorkspaceFile(url: URL(fileURLWithPath: "/tmp/App.swift"))
        #expect(swiftFile.systemImage == "swift")
        #expect(swiftFile.iconColor == .orange)

        let makefile = CEWorkspaceFile(url: URL(fileURLWithPath: "/tmp/Makefile"))
        #expect(makefile.systemImage == "terminal")
        #expect(makefile.iconColor == Self.makefileRed)

        let unknown = CEWorkspaceFile(url: URL(fileURLWithPath: "/tmp/blob.zzz"))
        #expect(unknown.systemImage == "doc.plaintext")
        #expect(unknown.iconColor == Color.steel)
    }

    @Test
    func rootDirectoryUsesBadgedFolderSymbol() throws {
        try withTempDir { dir in
            let root = CEWorkspaceFile(url: dir)
            #expect(root.isFolder)
            #expect(root.systemImage == "folder.fill.badge.gearshape")
        }
    }

    @Test
    func nestedDirectoryIconDependsOnContents() throws {
        try withTempDir { dir in
            let root = CEWorkspaceFile(url: dir)
            let emptyURL = dir.appending(path: "empty", directoryHint: .isDirectory)
            let fullURL = dir.appending(path: "full", directoryHint: .isDirectory)
            let configURL = dir.appending(path: ".dreamder", directoryHint: .isDirectory)
            for url in [emptyURL, fullURL, configURL] {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
            try "x".write(to: fullURL.appending(path: "a.txt"), atomically: true, encoding: .utf8)
            try "x".write(to: configURL.appending(path: "a.txt"), atomically: true, encoding: .utf8)

            let empty = CEWorkspaceFile(url: emptyURL)
            let full = CEWorkspaceFile(url: fullURL)
            let config = CEWorkspaceFile(url: configURL)
            for child in [empty, full, config] {
                child.parent = root
            }

            #expect(empty.systemImage == "folder")
            #expect(full.systemImage == "folder.fill")
            #expect(config.systemImage == "folder.fill.badge.gearshape")
        }
    }

    @Test
    func directoryNamedLikeKnownExtensionStillShowsFolderSymbol() throws {
        try withTempDir { dir in
            let root = CEWorkspaceFile(url: dir)
            let folderURL = dir.appending(path: "Sources.swift", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let folder = CEWorkspaceFile(url: folderURL)
            folder.parent = root
            #expect(folder.type == .swift)
            #expect(folder.systemImage == "folder")
        }
    }
}
