import Foundation
import Testing
@testable import Dreamder

struct CommentLanguageTests {
    struct ExtensionCase: Sendable, CustomStringConvertible {
        let fileExtension: String
        let expected: CommentLanguage

        var description: String { fileExtension }
    }

    struct FileNameCase: Sendable, CustomStringConvertible {
        let fileName: String
        let expected: CommentLanguage

        var description: String { fileName }
    }

    private static func extensionCases(_ extensions: [String], _ language: CommentLanguage) -> [ExtensionCase] {
        extensions.map { ExtensionCase(fileExtension: $0, expected: language) }
    }

    static let registeredExtensions: [ExtensionCase] = [
        extensionCases(["java", "groovy", "gradle"], .javaStyle),
        extensionCases(
            [
                "c", "h", "cpp", "cc", "cxx", "hpp", "hh", "hxx", "m", "mm", "swift", "kt", "kts", "scala", "sc",
                "go", "rs", "ts", "mts", "cts", "cs", "dart", "php", "proto", "zig", "sol",
                "cu", "cuh", "glsl", "vert", "frag", "metal", "vala", "d", "hx",
            ],
            .cFamily
        ),
        extensionCases(["jsx", "tsx", "js", "mjs", "cjs"], .jsx),
        extensionCases(["json", "jsonc", "json5", "webmanifest", "geojson"], .json),
        extensionCases(
            ["html", "htm", "xhtml", "xml", "svg", "xsd", "xsl", "xslt", "plist", "fxml", "vue", "md", "markdown", "dtd"],
            .markup
        ),
        extensionCases(["css"], .cssLike),
        extensionCases(["scss", "less"], .scssLike),
        extensionCases(
            [
                "py", "pyi", "rb", "sh", "bash", "zsh", "fish", "yml", "yaml", "toml", "conf", "r", "pl", "pm", "ex",
                "exs", "jl", "nim", "properties", "cmake", "mk", "gitignore", "dockerfile", "ps1", "tcl", "awk",
                "cfg", "env", "mak", "coffee", "cr", "tf", "hcl", "ru", "rake", "gemspec",
            ],
            .line(prefix: "#")
        ),
        extensionCases(["ini"], .line(prefix: ";")),
        extensionCases(["sql"], .line(prefix: "--", blockPrefix: "/*", blockSuffix: "*/")),
        extensionCases(["hs", "elm"], .line(prefix: "--", blockPrefix: "{-", blockSuffix: "-}")),
        extensionCases(["lua"], .line(prefix: "--", blockPrefix: "--[[", blockSuffix: "]]")),
        extensionCases(["lisp", "el", "clj", "cljs", "scm"], .line(prefix: ";")),
        extensionCases(["vim"], .line(prefix: "\"")),
        extensionCases(["bat", "cmd"], CommentLanguage(linePrefix: "REM ")),
        extensionCases(["tex", "sty", "cls", "bib", "erl", "hrl"], .line(prefix: "%")),
    ].flatMap { $0 }

    static let registeredFileNames: [FileNameCase] = [
        "Dockerfile", "Makefile", "GNUmakefile", "CMakeLists.txt", ".gitignore", ".gitattributes",
        ".dockerignore", ".editorconfig", ".env", "Gemfile", "Rakefile", "Podfile", ".bashrc",
        ".zshrc", ".profile", ".npmrc", "requirements.txt", "Procfile",
    ].map { FileNameCase(fileName: $0, expected: .line(prefix: "#")) }

    @Test
    func defaultLanguageSupportsNothing() {
        let language = CommentLanguage()

        #expect(language == .unsupported)
        #expect(language.linePrefix == nil)
        #expect(language.blockPrefix == nil)
        #expect(language.blockSuffix == nil)
        #expect(!language.isJsx)
        #expect(language.commentedBlockPrefix == nil)
        #expect(language.commentedBlockSuffix == nil)
        #expect(!language.escapesXmlDashes)
        #expect(!language.hasStringLiterals)
        #expect(!language.detectsCommentTokens)
        #expect(!language.lineCommentAtFirstColumn)
        #expect(!language.lineCommentAddsSpace)
        #expect(!language.blockCommentAtFirstColumn)
        #expect(!language.blockCommentAddsSpace)
        #expect(!language.supportsBlockComments)
        #expect(!language.supportsComments)
    }

    @Test
    func initializerStoresEveryProperty() {
        let language = CommentLanguage(
            linePrefix: "L",
            blockPrefix: "BP",
            blockSuffix: "BS",
            isJsx: true,
            commentedBlockPrefix: "CP",
            commentedBlockSuffix: "CS",
            escapesXmlDashes: true,
            hasStringLiterals: true,
            detectsCommentTokens: true,
            lineCommentAtFirstColumn: true,
            lineCommentAddsSpace: true,
            blockCommentAtFirstColumn: true,
            blockCommentAddsSpace: true
        )

        #expect(language.linePrefix == "L")
        #expect(language.blockPrefix == "BP")
        #expect(language.blockSuffix == "BS")
        #expect(language.isJsx)
        #expect(language.commentedBlockPrefix == "CP")
        #expect(language.commentedBlockSuffix == "CS")
        #expect(language.escapesXmlDashes)
        #expect(language.hasStringLiterals)
        #expect(language.detectsCommentTokens)
        #expect(language.lineCommentAtFirstColumn)
        #expect(language.lineCommentAddsSpace)
        #expect(language.blockCommentAtFirstColumn)
        #expect(language.blockCommentAddsSpace)
    }

    @Test
    func equalityComparesEveryProperty() {
        let base = CommentLanguage()
        let variants: [CommentLanguage] = [
            CommentLanguage(linePrefix: "x"),
            CommentLanguage(blockPrefix: "x"),
            CommentLanguage(blockSuffix: "x"),
            CommentLanguage(isJsx: true),
            CommentLanguage(commentedBlockPrefix: "x"),
            CommentLanguage(commentedBlockSuffix: "x"),
            CommentLanguage(escapesXmlDashes: true),
            CommentLanguage(hasStringLiterals: true),
            CommentLanguage(detectsCommentTokens: true),
            CommentLanguage(lineCommentAtFirstColumn: true),
            CommentLanguage(lineCommentAddsSpace: true),
            CommentLanguage(blockCommentAtFirstColumn: true),
            CommentLanguage(blockCommentAddsSpace: true),
        ]

        for variant in variants {
            #expect(variant != base)
        }
        #expect(base == CommentLanguage())
    }

    @Test
    func blockSupportNeedsBothPrefixAndSuffix() {
        #expect(!CommentLanguage(blockPrefix: "/*").supportsBlockComments)
        #expect(!CommentLanguage(blockSuffix: "*/").supportsBlockComments)
        #expect(CommentLanguage(blockPrefix: "/*", blockSuffix: "*/").supportsBlockComments)
    }

    @Test
    func commentSupportNeedsALinePrefixOrACompleteBlockPair() {
        #expect(CommentLanguage(linePrefix: "#").supportsComments)
        #expect(CommentLanguage(blockPrefix: "/*", blockSuffix: "*/").supportsComments)
        #expect(!CommentLanguage(blockPrefix: "/*").supportsComments)
        #expect(!CommentLanguage(blockSuffix: "*/").supportsComments)
        #expect(!CommentLanguage.unsupported.supportsComments)
    }

    @Test
    func jsxMarkupWrapsInBracedBlockCommentsWithSpaces() {
        let markup = CommentLanguage.jsx.jsxMarkup

        #expect(CommentLanguage.jsxMarkupPrefix == "{/*")
        #expect(CommentLanguage.jsxMarkupSuffix == "*/}")
        #expect(markup == CommentLanguage(blockPrefix: "{/*", blockSuffix: "*/}", blockCommentAddsSpace: true))
        #expect(markup.linePrefix == nil)
        #expect(!markup.isJsx)
        #expect(markup.supportsBlockComments)
        #expect(CommentLanguage.javaStyle.jsxMarkup == markup)
    }

    @Test
    func javaStyleFollowsTheJavaCommenterWithFirstColumnLineComments() {
        #expect(
            CommentLanguage.javaStyle == CommentLanguage(
                linePrefix: "//",
                blockPrefix: "/*",
                blockSuffix: "*/",
                hasStringLiterals: true,
                detectsCommentTokens: true,
                lineCommentAtFirstColumn: true,
                blockCommentAtFirstColumn: true
            )
        )
    }

    @Test
    func cFamilyIndentsLineCommentsAndAddsASpace() {
        #expect(
            CommentLanguage.cFamily == CommentLanguage(
                linePrefix: "//",
                blockPrefix: "/*",
                blockSuffix: "*/",
                hasStringLiterals: true,
                detectsCommentTokens: true,
                lineCommentAddsSpace: true
            )
        )
    }

    @Test
    func jsxIsACFamilyLanguageWithMarkup() {
        var expected = CommentLanguage.cFamily
        expected.isJsx = true

        #expect(CommentLanguage.jsx == expected)
        #expect(CommentLanguage.jsx.isJsx)
        #expect(!CommentLanguage.cFamily.isJsx)
    }

    @Test
    func jsonHasLineAndBlockCommentsWithFirstColumnLineComments() {
        let json = CommentLanguage.json

        #expect(json.linePrefix == "//")
        #expect(json.blockPrefix == "/*")
        #expect(json.blockSuffix == "*/")
        #expect(json.commentedBlockPrefix == nil)
        #expect(json.commentedBlockSuffix == nil)
        #expect(json.lineCommentAtFirstColumn)
        #expect(!json.lineCommentAddsSpace)
        #expect(json.supportsBlockComments)
        #expect(json.supportsComments)
        #expect(!json.isJsx)
        #expect(!json.detectsCommentTokens)
        #expect(json.hasStringLiterals)
    }

    @Test
    func markupEscapesNestedCommentsAsXmlEntities() {
        #expect(
            CommentLanguage.markup == CommentLanguage(
                blockPrefix: "<!--",
                blockSuffix: "-->",
                commentedBlockPrefix: "&lt;!&ndash;",
                commentedBlockSuffix: "&ndash;&gt;",
                escapesXmlDashes: true,
                lineCommentAtFirstColumn: true,
                blockCommentAtFirstColumn: true
            )
        )
        #expect(CommentLanguage.markup.linePrefix == nil)
    }

    @Test
    func cssAndScssAddSpacesInsideBlockComments() {
        #expect(
            CommentLanguage.cssLike == CommentLanguage(
                blockPrefix: "/*",
                blockSuffix: "*/",
                hasStringLiterals: true,
                blockCommentAddsSpace: true
            )
        )
        #expect(
            CommentLanguage.scssLike == CommentLanguage(
                linePrefix: "//",
                blockPrefix: "/*",
                blockSuffix: "*/",
                hasStringLiterals: true,
                lineCommentAddsSpace: true,
                blockCommentAddsSpace: true
            )
        )
    }

    @Test
    func lineFactoriesAddASpaceAfterThePrefix() {
        #expect(CommentLanguage.line(prefix: "#") == CommentLanguage(linePrefix: "#", lineCommentAddsSpace: true))
        #expect(
            CommentLanguage.line(prefix: "--", blockPrefix: "{-", blockSuffix: "-}") == CommentLanguage(
                linePrefix: "--",
                blockPrefix: "{-",
                blockSuffix: "-}",
                lineCommentAddsSpace: true
            )
        )
    }

    @Test
    func missingURLIsUnsupported() {
        #expect(CommentLanguage.forFile(url: nil) == .unsupported)
    }

    @Test(arguments: CommentLanguageTests.registeredExtensions)
    func extensionsMapToTheirLanguage(testCase: ExtensionCase) {
        let url = URL(filePath: "/project/src/Sample.\(testCase.fileExtension)")

        #expect(CommentLanguage.forFile(url: url) == testCase.expected)
        #expect(CommentLanguage.forFile(url: URL(filePath: "/project/Sample.\(testCase.fileExtension.uppercased())")) == testCase.expected)
    }

    @Test(arguments: CommentLanguageTests.registeredFileNames)
    func fileNamesMapToTheirLanguage(testCase: FileNameCase) {
        #expect(CommentLanguage.forFile(url: URL(filePath: "/project/\(testCase.fileName)")) == testCase.expected)
        #expect(CommentLanguage.forFile(url: URL(filePath: "/project/\(testCase.fileName.uppercased())")) == testCase.expected)
    }

    @Test
    func fileNamesTakePrecedenceOverExtensions() {
        #expect(CommentLanguage.forFile(url: URL(filePath: "/p/requirements.txt")) == .line(prefix: "#"))
        #expect(CommentLanguage.forFile(url: URL(filePath: "/p/notes.txt")) == .unsupported)
        #expect(CommentLanguage.forFile(url: URL(filePath: "/p/Sample.txt")) == .unsupported)
    }

    @Test
    func unknownNamesAndExtensionsAreUnsupported() {
        #expect(CommentLanguage.forFile(url: URL(filePath: "/p/Sample.unknownext")) == .unsupported)
        #expect(CommentLanguage.forFile(url: URL(filePath: "/p/Sample")) == .unsupported)
        #expect(CommentLanguage.forFile(url: URL(filePath: "/p/")) == .unsupported)
    }

    @Test
    func everyRegisteredExtensionIsUnique() {
        let extensions = Self.registeredExtensions.map(\.fileExtension)

        #expect(Set(extensions).count == extensions.count)
    }
}
