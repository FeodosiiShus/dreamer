import Foundation

nonisolated struct CommentLanguage: Equatable, Sendable {
    var linePrefix: String?
    var blockPrefix: String?
    var blockSuffix: String?
    var isJsx: Bool
    var commentedBlockPrefix: String?
    var commentedBlockSuffix: String?
    var escapesXmlDashes: Bool
    var hasStringLiterals: Bool
    var detectsCommentTokens: Bool
    var lineCommentAtFirstColumn: Bool
    var lineCommentAddsSpace: Bool
    var blockCommentAtFirstColumn: Bool
    var blockCommentAddsSpace: Bool

    init(
        linePrefix: String? = nil,
        blockPrefix: String? = nil,
        blockSuffix: String? = nil,
        isJsx: Bool = false,
        commentedBlockPrefix: String? = nil,
        commentedBlockSuffix: String? = nil,
        escapesXmlDashes: Bool = false,
        hasStringLiterals: Bool = false,
        detectsCommentTokens: Bool = false,
        lineCommentAtFirstColumn: Bool = false,
        lineCommentAddsSpace: Bool = false,
        blockCommentAtFirstColumn: Bool = false,
        blockCommentAddsSpace: Bool = false
    ) {
        self.linePrefix = linePrefix
        self.blockPrefix = blockPrefix
        self.blockSuffix = blockSuffix
        self.isJsx = isJsx
        self.commentedBlockPrefix = commentedBlockPrefix
        self.commentedBlockSuffix = commentedBlockSuffix
        self.escapesXmlDashes = escapesXmlDashes
        self.hasStringLiterals = hasStringLiterals
        self.detectsCommentTokens = detectsCommentTokens
        self.lineCommentAtFirstColumn = lineCommentAtFirstColumn
        self.lineCommentAddsSpace = lineCommentAddsSpace
        self.blockCommentAtFirstColumn = blockCommentAtFirstColumn
        self.blockCommentAddsSpace = blockCommentAddsSpace
    }

    var supportsBlockComments: Bool { blockPrefix != nil && blockSuffix != nil }

    var supportsComments: Bool { linePrefix != nil || supportsBlockComments }

    static let jsxMarkupPrefix = "{/*"
    static let jsxMarkupSuffix = "*/}"

    var jsxMarkup: CommentLanguage {
        CommentLanguage(blockPrefix: Self.jsxMarkupPrefix, blockSuffix: Self.jsxMarkupSuffix, blockCommentAddsSpace: true)
    }

    static let unsupported = CommentLanguage()

    static let javaStyle = CommentLanguage(
        linePrefix: "//",
        blockPrefix: "/*",
        blockSuffix: "*/",
        hasStringLiterals: true,
        detectsCommentTokens: true,
        lineCommentAtFirstColumn: true,
        blockCommentAtFirstColumn: true
    )

    static let cFamily = CommentLanguage(
        linePrefix: "//",
        blockPrefix: "/*",
        blockSuffix: "*/",
        hasStringLiterals: true,
        detectsCommentTokens: true,
        lineCommentAddsSpace: true
    )

    static let jsx = CommentLanguage(
        linePrefix: "//",
        blockPrefix: "/*",
        blockSuffix: "*/",
        isJsx: true,
        hasStringLiterals: true,
        detectsCommentTokens: true,
        lineCommentAddsSpace: true
    )

    static let json = CommentLanguage(
        linePrefix: "//",
        blockPrefix: "/*",
        blockSuffix: "*/",
        hasStringLiterals: true,
        lineCommentAtFirstColumn: true
    )

    static let markup = CommentLanguage(
        blockPrefix: "<!--",
        blockSuffix: "-->",
        commentedBlockPrefix: "&lt;!&ndash;",
        commentedBlockSuffix: "&ndash;&gt;",
        escapesXmlDashes: true,
        lineCommentAtFirstColumn: true,
        blockCommentAtFirstColumn: true
    )

    static let cssLike = CommentLanguage(
        blockPrefix: "/*",
        blockSuffix: "*/",
        hasStringLiterals: true,
        blockCommentAddsSpace: true
    )

    static let scssLike = CommentLanguage(
        linePrefix: "//",
        blockPrefix: "/*",
        blockSuffix: "*/",
        hasStringLiterals: true,
        lineCommentAddsSpace: true,
        blockCommentAddsSpace: true
    )

    static func line(prefix: String) -> CommentLanguage {
        CommentLanguage(linePrefix: prefix, lineCommentAddsSpace: true)
    }

    static func line(prefix: String, blockPrefix: String, blockSuffix: String) -> CommentLanguage {
        CommentLanguage(
            linePrefix: prefix,
            blockPrefix: blockPrefix,
            blockSuffix: blockSuffix,
            lineCommentAddsSpace: true
        )
    }

    static func forFile(url: URL?) -> CommentLanguage {
        guard let url else { return .unsupported }
        let fileName = url.lastPathComponent.lowercased()
        if let byName = languagesByFileName[fileName] { return byName }
        return languagesByExtension[url.pathExtension.lowercased()] ?? .unsupported
    }

    private static let languagesByFileName: [String: CommentLanguage] = {
        var table: [String: CommentLanguage] = [:]
        let hashNames = [
            "dockerfile", "makefile", "gnumakefile", "cmakelists.txt", ".gitignore", ".gitattributes",
            ".dockerignore", ".editorconfig", ".env", "gemfile", "rakefile", "podfile", ".bashrc",
            ".zshrc", ".profile", ".npmrc", "requirements.txt", "procfile",
        ]
        for name in hashNames { table[name] = .line(prefix: "#") }
        return table
    }()

    private static let languagesByExtension: [String: CommentLanguage] = {
        var table: [String: CommentLanguage] = [:]
        func register(_ extensions: [String], _ language: CommentLanguage) {
            for fileExtension in extensions { table[fileExtension] = language }
        }
        register(["java", "groovy", "gradle"], .javaStyle)
        register(
            [
                "c", "h", "cpp", "cc", "cxx", "hpp", "hh", "hxx", "m", "mm", "swift", "kt", "kts", "scala", "sc",
                "go", "rs", "ts", "mts", "cts", "cs", "dart", "php", "proto", "zig", "sol",
                "cu", "cuh", "glsl", "vert", "frag", "metal", "vala", "d", "hx",
            ],
            .cFamily
        )
        register(["jsx", "tsx", "js", "mjs", "cjs"], .jsx)
        register(["json", "jsonc", "json5", "webmanifest", "geojson"], .json)
        register(
            ["html", "htm", "xhtml", "xml", "svg", "xsd", "xsl", "xslt", "plist", "fxml", "vue", "md", "markdown", "dtd"],
            .markup
        )
        register(["css"], .cssLike)
        register(["scss", "less"], .scssLike)
        register(
            [
                "py", "pyi", "rb", "sh", "bash", "zsh", "fish", "yml", "yaml", "toml", "conf", "r", "pl", "pm", "ex",
                "exs", "jl", "nim", "properties", "cmake", "mk", "gitignore", "dockerfile", "ps1", "tcl", "awk",
                "cfg", "env", "mak", "coffee", "cr", "tf", "hcl", "ru", "rake", "gemspec",
            ],
            .line(prefix: "#")
        )
        register(["ini"], .line(prefix: ";"))
        register(["sql"], .line(prefix: "--", blockPrefix: "/*", blockSuffix: "*/"))
        register(["hs", "elm"], .line(prefix: "--", blockPrefix: "{-", blockSuffix: "-}"))
        register(["lua"], .line(prefix: "--", blockPrefix: "--[[", blockSuffix: "]]"))
        register(["lisp", "el", "clj", "cljs", "scm"], .line(prefix: ";"))
        register(["vim"], .line(prefix: "\""))
        register(["bat", "cmd"], CommentLanguage(linePrefix: "REM "))
        register(["tex", "sty", "cls", "bib", "erl", "hrl"], .line(prefix: "%"))
        return table
    }()
}
