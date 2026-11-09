//
//  LanguageIdentifier+CodeLanguage.swift
//  Dreamder
//
//  Created by Khan Winter on 9/9/24.
//

import LanguageServerProtocol
import CodeEditLanguages

extension CodeLanguage {
    var lspLanguage: LSPLanguage? {
        switch self.id {
        case .agda,
                .haskell,
                .julia,
                .ocaml,
                .ocamlInterface,
                .regex,
                .verilog,
                .zig,
                .plainText:
            return nil
        case .bash:
            return .shellscript
        case .kotlin:
            return .kotlin
        case .toml:
            return .toml
        case .c:
            return .c
        case .cpp:
            return .cpp
        case .cSharp:
            return LSPLanguage(.csharp)
        case .css:
            return .css
        case .dart:
            return LSPLanguage(.dart)
        case .dockerfile:
            return LSPLanguage(.dockerfile)
        case .elixir:
            return LSPLanguage(.elixir)
        case .go, .goMod:
            return .go
        case .html:
            return .html
        case .java:
            return .java
        case .javascript, .jsdoc:
            return .javascript
        case .json:
            return .json
        case .jsx:
            return .javascriptreact
        case .lua:
            return LSPLanguage(.lua)
        case .markdown, .markdownInline:
            return LSPLanguage(.markdown)
        case .objc:
            return .objc
        case .perl:
            return LSPLanguage(.perl)
        case .php:
            return LSPLanguage(.php)
        case .python:
            return .python
        case .ruby:
            return LSPLanguage(.ruby)
        case .rust:
            return .rust
        case .scala:
            return LSPLanguage(.scala)
        case .sql:
            return LSPLanguage(.sql)
        case .swift:
            return .swift
        case .tsx:
            return .typescriptreact
        case .typescript:
            return .typescript
        case .yaml:
            return .yaml
        }
    }

    var lspLanguageId: String {
        lspLanguage?.rawValue ?? "plaintext"
    }
}
