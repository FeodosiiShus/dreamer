import Foundation

nonisolated enum IndentStyle: Equatable, Sendable {
    case tab
    case spaces
}

nonisolated enum IndentSource: Equatable, Sendable {
    case documentOverride
    case editorConfig
    case detected
    case languageDefault
    case global
}

nonisolated struct IndentLayer: Equatable, Sendable {
    var style: IndentStyle?
    var spaceCount: Int?
    var tabWidth: Int?

    static let empty = IndentLayer(style: nil, spaceCount: nil, tabWidth: nil)

    init(style: IndentStyle? = nil, spaceCount: Int? = nil, tabWidth: Int? = nil) {
        self.style = style
        self.spaceCount = spaceCount
        self.tabWidth = tabWidth
    }

    init(editorConfig: EditorConfigProperties) {
        switch editorConfig.indentStyle {
        case .tab:
            style = .tab
        case .space:
            style = .spaces
        case nil:
            style = nil
        }
        spaceCount = editorConfig.indentSize
        tabWidth = editorConfig.tabWidth
    }

    init(detected: DetectedIndent?) {
        switch detected {
        case .tabs:
            self.init(style: .tab)
        case .spaces(let size):
            self.init(style: .spaces, spaceCount: size)
        case nil:
            self.init()
        }
    }
}

nonisolated struct GlobalIndent: Equatable, Sendable {
    var style: IndentStyle
    var spaceCount: Int
    var tabWidth: Int
}

nonisolated struct ResolvedIndent: Equatable, Sendable {
    var style: IndentStyle
    var spaceCount: Int
    var tabWidth: Int
    var styleSource: IndentSource
}

nonisolated enum IndentResolver {
    static func resolve(
        documentOverride: IndentLayer,
        editorConfig: EditorConfigProperties,
        detected: DetectedIndent?,
        languageDefault: IndentLayer,
        global: GlobalIndent
    ) -> ResolvedIndent {
        let layers: [(IndentSource, IndentLayer)] = [
            (.documentOverride, documentOverride),
            (.editorConfig, IndentLayer(editorConfig: editorConfig)),
            (.detected, IndentLayer(detected: detected)),
            (.languageDefault, languageDefault)
        ]
        let styleLayer = layers.first { $0.1.style != nil }
        return ResolvedIndent(
            style: styleLayer?.1.style ?? global.style,
            spaceCount: layers.lazy.compactMap { $0.1.spaceCount }.first ?? global.spaceCount,
            tabWidth: layers.lazy.compactMap { $0.1.tabWidth }.first ?? global.tabWidth,
            styleSource: styleLayer?.0 ?? .global
        )
    }
}

nonisolated enum LanguageIndentDefaults {
    private static let makefileNames: Set<String> = ["makefile", "gnumakefile"]
    private static let makefileExtensions: Set<String> = ["mk", "mak"]
    private static let pythonExtensions: Set<String> = ["py", "pyi", "pyw"]
    private static let pythonSpaceCount = 4

    static func layer(for fileURL: URL?) -> IndentLayer {
        guard let fileURL else { return .empty }
        let name = fileURL.lastPathComponent.lowercased()
        let pathExtension = fileURL.pathExtension.lowercased()
        if pathExtension == "go" || makefileNames.contains(name) || makefileExtensions.contains(pathExtension) {
            return IndentLayer(style: .tab)
        }
        if pythonExtensions.contains(pathExtension) {
            return IndentLayer(style: .spaces, spaceCount: pythonSpaceCount)
        }
        return .empty
    }
}
