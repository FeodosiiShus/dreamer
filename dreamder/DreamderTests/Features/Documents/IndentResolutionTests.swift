import Foundation
import Testing
@testable import Dreamder

@Suite
struct IndentResolutionTests {
    static let global = GlobalIndent(style: .spaces, spaceCount: 4, tabWidth: 4)

    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        var documentOverride = IndentLayer.empty
        var editorConfig = EditorConfigProperties.empty
        var detected: DetectedIndent?
        var languageDefault = IndentLayer.empty
        var global = IndentResolutionTests.global
        let expected: ResolvedIndent

        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(
            name: "nothing configured falls back to the global setting",
            expected: ResolvedIndent(style: .spaces, spaceCount: 4, tabWidth: 4, styleSource: .global)
        ),
        Case(
            name: "global tabs are used when nothing else applies",
            global: GlobalIndent(style: .tab, spaceCount: 2, tabWidth: 8),
            expected: ResolvedIndent(style: .tab, spaceCount: 2, tabWidth: 8, styleSource: .global)
        ),
        Case(
            name: "language default beats global",
            languageDefault: IndentLayer(style: .tab),
            expected: ResolvedIndent(style: .tab, spaceCount: 4, tabWidth: 4, styleSource: .languageDefault)
        ),
        Case(
            name: "detection beats the language default",
            detected: .spaces(size: 2),
            languageDefault: IndentLayer(style: .tab),
            expected: ResolvedIndent(style: .spaces, spaceCount: 2, tabWidth: 4, styleSource: .detected)
        ),
        Case(
            name: "detected tabs beat a spaces language default",
            detected: .tabs,
            languageDefault: IndentLayer(style: .spaces, spaceCount: 4),
            expected: ResolvedIndent(style: .tab, spaceCount: 4, tabWidth: 4, styleSource: .detected)
        ),
        Case(
            name: "editorconfig beats detection",
            editorConfig: EditorConfigProperties(indentStyle: .tab, tabWidth: 3),
            detected: .spaces(size: 2),
            expected: ResolvedIndent(style: .tab, spaceCount: 2, tabWidth: 3, styleSource: .editorConfig)
        ),
        Case(
            name: "editorconfig spaces size beats detected size",
            editorConfig: EditorConfigProperties(indentStyle: .space, indentSize: 8, tabWidth: 8),
            detected: .spaces(size: 2),
            expected: ResolvedIndent(style: .spaces, spaceCount: 8, tabWidth: 8, styleSource: .editorConfig)
        ),
        Case(
            name: "document override beats editorconfig",
            documentOverride: IndentLayer(style: .spaces, spaceCount: 6, tabWidth: 5),
            editorConfig: EditorConfigProperties(indentStyle: .tab, indentSize: 3, tabWidth: 3),
            detected: .tabs,
            languageDefault: IndentLayer(style: .tab),
            expected: ResolvedIndent(style: .spaces, spaceCount: 6, tabWidth: 5, styleSource: .documentOverride)
        ),
        Case(
            name: "editorconfig size without style keeps the style from detection",
            editorConfig: EditorConfigProperties(indentSize: 3, tabWidth: 3),
            detected: .spaces(size: nil),
            expected: ResolvedIndent(style: .spaces, spaceCount: 3, tabWidth: 3, styleSource: .detected)
        ),
        Case(
            name: "editorconfig without indent properties does not mask detection",
            editorConfig: EditorConfigProperties(endOfLine: .lf, insertFinalNewline: true),
            detected: .tabs,
            expected: ResolvedIndent(style: .tab, spaceCount: 4, tabWidth: 4, styleSource: .detected)
        ),
        Case(
            name: "override of tab width alone keeps the detected style",
            documentOverride: IndentLayer(tabWidth: 2),
            detected: .spaces(size: 2),
            expected: ResolvedIndent(style: .spaces, spaceCount: 2, tabWidth: 2, styleSource: .detected)
        )
    ]

    @Test(arguments: cases)
    func resolvesByPrecedence(_ testCase: Case) {
        let resolved = IndentResolver.resolve(
            documentOverride: testCase.documentOverride,
            editorConfig: testCase.editorConfig,
            detected: testCase.detected,
            languageDefault: testCase.languageDefault,
            global: testCase.global
        )

        #expect(resolved == testCase.expected)
    }

    struct LanguageCase: Sendable, CustomTestStringConvertible {
        let path: String?
        let expected: IndentLayer

        var testDescription: String { path ?? "nil" }
    }

    static let languageCases: [LanguageCase] = [
        LanguageCase(path: nil, expected: .empty),
        LanguageCase(path: "/p/main.go", expected: IndentLayer(style: .tab)),
        LanguageCase(path: "/p/MAIN.GO", expected: IndentLayer(style: .tab)),
        LanguageCase(path: "/p/Makefile", expected: IndentLayer(style: .tab)),
        LanguageCase(path: "/p/makefile", expected: IndentLayer(style: .tab)),
        LanguageCase(path: "/p/GNUmakefile", expected: IndentLayer(style: .tab)),
        LanguageCase(path: "/p/rules.mk", expected: IndentLayer(style: .tab)),
        LanguageCase(path: "/p/rules.mak", expected: IndentLayer(style: .tab)),
        LanguageCase(path: "/p/tool.py", expected: IndentLayer(style: .spaces, spaceCount: 4)),
        LanguageCase(path: "/p/tool.pyi", expected: IndentLayer(style: .spaces, spaceCount: 4)),
        LanguageCase(path: "/p/tool.pyw", expected: IndentLayer(style: .spaces, spaceCount: 4)),
        LanguageCase(path: "/p/index.ts", expected: .empty),
        LanguageCase(path: "/p/Makefile.txt", expected: .empty)
    ]

    @Test(arguments: languageCases)
    func languageDefaults(_ testCase: LanguageCase) {
        let url = testCase.path.map { URL(fileURLWithPath: $0) }

        #expect(LanguageIndentDefaults.layer(for: url) == testCase.expected)
    }

    @Test
    func editorConfigLayerMapsStyleSizeAndTabWidth() {
        let tab = IndentLayer(editorConfig: EditorConfigProperties(indentStyle: .tab, indentSize: 4, tabWidth: 8))
        let space = IndentLayer(editorConfig: EditorConfigProperties(indentStyle: .space, indentSize: 2))
        let none = IndentLayer(editorConfig: .empty)

        #expect(tab == IndentLayer(style: .tab, spaceCount: 4, tabWidth: 8))
        #expect(space == IndentLayer(style: .spaces, spaceCount: 2, tabWidth: nil))
        #expect(none == .empty)
    }

    @Test
    func detectedLayerMapsTabsSpacesAndNothing() {
        #expect(IndentLayer(detected: .tabs) == IndentLayer(style: .tab))
        #expect(IndentLayer(detected: .spaces(size: 3)) == IndentLayer(style: .spaces, spaceCount: 3))
        #expect(IndentLayer(detected: .spaces(size: nil)) == IndentLayer(style: .spaces))
        #expect(IndentLayer(detected: nil) == .empty)
    }
}
