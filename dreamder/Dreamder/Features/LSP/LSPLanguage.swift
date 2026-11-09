import Foundation
import LanguageServerProtocol

nonisolated struct LSPLanguage: Hashable, Sendable, RawRepresentable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ identifier: LanguageIdentifier) {
        self.rawValue = identifier.rawValue
    }

    static let swift = LSPLanguage(.swift)
    static let objc = LSPLanguage(.objc)
    static let objcpp = LSPLanguage(.objcpp)
    static let c = LSPLanguage(.c)
    static let cpp = LSPLanguage(.cpp)
    static let typescript = LSPLanguage(.typescript)
    static let javascript = LSPLanguage(.javascript)
    static let typescriptreact = LSPLanguage(.typescriptreact)
    static let javascriptreact = LSPLanguage(.javascriptreact)
    static let python = LSPLanguage(.python)
    static let go = LSPLanguage(.go)
    static let rust = LSPLanguage(.rust)
    static let json = LSPLanguage(.json)
    static let css = LSPLanguage(.css)
    static let scss = LSPLanguage(.scss)
    static let less = LSPLanguage(.less)
    static let html = LSPLanguage(.html)
    static let java = LSPLanguage(.java)
    static let yaml = LSPLanguage(.yaml)
    static let shellscript = LSPLanguage(.shellscript)
    static let kotlin = LSPLanguage(rawValue: "kotlin")
    static let toml = LSPLanguage(rawValue: "toml")

    static let known: [LSPLanguage] = LanguageIdentifier.allCases.map(LSPLanguage.init) + [.kotlin, .toml]

    static var knownRawValues: [String] {
        known.map(\.rawValue)
    }

    private static let typeScriptFamily: Set<LSPLanguage> = [.typescript, .javascript, .typescriptreact, .javascriptreact]
    private static let styleSheetFamily: Set<LSPLanguage> = [.css, .scss, .less]
    private static let clangFamily: Set<LSPLanguage> = [.c, .cpp, .objcpp]
    private static let sourceKitFamily: Set<LSPLanguage> = [.swift, .objc]

    var serverFamily: LSPLanguage {
        if Self.typeScriptFamily.contains(self) { return .typescript }
        if Self.styleSheetFamily.contains(self) { return .css }
        if Self.clangFamily.contains(self) { return .c }
        if Self.sourceKitFamily.contains(self) { return .swift }
        return self
    }

    var familyMembers: [LSPLanguage] {
        let family = serverFamily
        return Self.known.filter { $0.serverFamily == family }
    }
}
