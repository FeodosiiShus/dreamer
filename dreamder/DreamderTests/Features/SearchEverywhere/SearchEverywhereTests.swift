import Foundation
import Testing
@testable import Dreamder

@Suite("SearchEverywhereMatcher")
struct SearchEverywhereMatcherTests {
    @Test func rankingExactThenPrefixThenSubstringThenOtherHumps() throws {
        let exact = try #require(SearchEverywhereMatcher.match(query: "ContentView", in: "ContentView"))
        let prefix = try #require(SearchEverywhereMatcher.match(query: "ContentView", in: "ContentViewDetail"))
        let midWordStart = try #require(SearchEverywhereMatcher.match(query: "ContentView", in: "MyContentViewThing"))

        #expect(exact.score > prefix.score)
        #expect(prefix.score > midWordStart.score)
    }

    @Test func startMatchesOutrankEverythingElse() throws {
        let startMatch = try #require(SearchEverywhereMatcher.match(query: "view", in: "ViewModel"))
        let middleMatch = try #require(SearchEverywhereMatcher.match(query: "view", in: "ContentView"))
        #expect(startMatch.score - middleMatch.score >= 9000)
    }

    @Test func noMatchForUnrelatedQuery() {
        #expect(SearchEverywhereMatcher.match(query: "zzq", in: "ContentView") == nil)
    }

    @Test func emptyQueryMatchesEverything() {
        let match = SearchEverywhereMatcher.match(query: "", in: "ContentView")
        #expect(match?.score == 0)
        #expect(match?.ranges == [])
    }

    @Test func whitespaceOnlyQueryMatchesEverything() {
        let match = SearchEverywhereMatcher.match(query: "   ", in: "ContentView")
        #expect(match?.score == 0)
        #expect(match?.ranges == [])
    }

    @Test func emptyCandidateNeverMatchesARealQuery() {
        #expect(SearchEverywhereMatcher.match(query: "a", in: "") == nil)
    }

    @Test func camelHumpMatchesMultipleWords() {
        let match = SearchEverywhereMatcher.match(query: "DWFM", in: "DreamderWorkspaceFileManager")
        #expect(
            match?.ranges == [
                NSRange(location: 0, length: 1),
                NSRange(location: 8, length: 1),
                NSRange(location: 17, length: 1),
                NSRange(location: 21, length: 1)
            ]
        )
    }

    @Test func lowercaseHumpsMatchWordPrefixes() {
        let match = SearchEverywhereMatcher.match(query: "conview", in: "ContentView")
        #expect(match?.ranges == [NSRange(location: 0, length: 3), NSRange(location: 7, length: 4)])
    }

    @Test func mixedCaseHumpsMatchWordPrefixes() {
        let match = SearchEverywhereMatcher.match(query: "UsSe", in: "UserService")
        #expect(match?.ranges == [NSRange(location: 0, length: 2), NSRange(location: 4, length: 2)])
    }

    @Test func caseInsensitivePrefix() {
        let match = SearchEverywhereMatcher.match(query: "openquick", in: "OpenQuicklyView")
        #expect(match?.ranges == [NSRange(location: 0, length: 9)])
    }

    @Test func substringHighlightRange() {
        let match = SearchEverywhereMatcher.match(query: "Quickly", in: "MyQuicklyView")
        #expect(match?.ranges == [NSRange(location: 2, length: 7)])
    }

    @Test func allCapsAcronymWordStartsAreHonored() {
        let match = SearchEverywhereMatcher.match(query: "Serv", in: "HTTPServer")
        #expect(match?.ranges == [NSRange(location: 4, length: 4)])
    }

    @Test func lowercaseLetterInsideWordNeedsThreeCharacters() {
        #expect(SearchEverywhereMatcher.match(query: "ogn", in: "login") == nil)
        #expect(SearchEverywhereMatcher.match(query: "pcl", in: "ApplicationController") == nil)
        #expect(SearchEverywhereMatcher.match(query: "ogi", in: "login")?.ranges == [NSRange(location: 1, length: 3)])
        #expect(SearchEverywhereMatcher.match(query: "ogin", in: "login") != nil)
    }

    @Test func leadingStarIsNotDoubled() {
        let plain = SearchEverywhereMatcher.match(query: "view", in: "ContentView")
        let starred = SearchEverywhereMatcher.match(query: "*view", in: "ContentView")
        #expect(plain == starred)
    }

    @Test func surroundingWhitespaceIsIgnored() {
        let plain = SearchEverywhereMatcher.match(query: "view", in: "ContentView")
        let padded = SearchEverywhereMatcher.match(query: "  view  ", in: "ContentView")
        #expect(plain == padded)
    }

    @Test func russianLayoutQueryFindsLatinName() {
        let match = SearchEverywhereMatcher.match(query: "ыек", in: "StringUtils")
        #expect(match?.ranges == [NSRange(location: 0, length: 3)])
    }

    @Test func rangesAreUTF16Offsets() {
        let match = SearchEverywhereMatcher.match(query: "Foo", in: "\u{1F600}Foo")
        #expect(match?.ranges == [NSRange(location: 2, length: 3)])
    }

    @Test func cachedMatcherIsReusedForTheSameQueryOnly() {
        let first = SearchEverywhereMatcher.match(query: "alpha", in: "AlphaBeta")
        let other = SearchEverywhereMatcher.match(query: "beta", in: "AlphaBeta")
        let again = SearchEverywhereMatcher.match(query: "alpha", in: "AlphaBeta")
        #expect(first == again)
        #expect(first?.ranges == [NSRange(location: 0, length: 5)])
        #expect(other?.ranges == [NSRange(location: 5, length: 4)])
    }

    @Test func matcherMatchesUsingPrebuiltMatcher() {
        let matcher = SearchEverywhereMatcher.matcher(for: "cv")
        #expect(SearchEverywhereMatcher.match(using: matcher, in: "ContentView")?.ranges
            == [NSRange(location: 0, length: 1), NSRange(location: 7, length: 1)])
        #expect(SearchEverywhereMatcher.match(using: matcher, in: "Other") == nil)
    }
}

@Suite("SearchEverywhereQuery")
struct SearchEverywhereQueryTests {
    @Test func plainQueryHasNoLine() {
        let parsed = SearchEverywhereQuery.parse("ContentView.swift")
        #expect(parsed.text == "ContentView.swift")
        #expect(parsed.line == nil)
        #expect(parsed.column == nil)
    }

    @Test func lineSuffix() {
        let parsed = SearchEverywhereQuery.parse("ContentView.swift:42")
        #expect(parsed.text == "ContentView.swift")
        #expect(parsed.line == 42)
        #expect(parsed.column == nil)
    }

    @Test func lineAndColumnSuffix() {
        let parsed = SearchEverywhereQuery.parse("ContentView.swift:42:7")
        #expect(parsed.text == "ContentView.swift")
        #expect(parsed.line == 42)
        #expect(parsed.column == 7)
    }

    @Test func colonInNameIsKept() {
        let parsed = SearchEverywhereQuery.parse("app:server")
        #expect(parsed.text == "app:server")
        #expect(parsed.line == nil)
    }

    @Test func urlLikeQueryIsUntouched() {
        let parsed = SearchEverywhereQuery.parse("https://example.com")
        #expect(parsed.text == "https://example.com")
        #expect(parsed.line == nil)
    }

    @Test func numericOnlyQueryIsNotSuffix() {
        let parsed = SearchEverywhereQuery.parse(":42")
        #expect(parsed.text == ":42")
        #expect(parsed.line == nil)
    }

    @Test func surroundingWhitespaceIsTrimmed() {
        let parsed = SearchEverywhereQuery.parse("  App.swift:12  ")
        #expect(parsed.text == "App.swift")
        #expect(parsed.line == 12)
    }

    @Test func emptyAndBlankQueries() {
        #expect(SearchEverywhereQuery.parse("") == SearchEverywhereQuery(text: ""))
        #expect(SearchEverywhereQuery.parse("   ") == SearchEverywhereQuery(text: ""))
    }

    @Test(arguments: [
        ("Foo.swift:12", 12, nil),
        ("Foo.swift@12", 12, nil),
        ("Foo.swift,12", 12, nil),
        ("Foo.swift 12", 12, nil),
        ("Foo.swift#12", 12, nil),
        ("Foo.swift#L12", 12, nil),
        ("Foo.swift?l=12", 12, nil),
        ("Foo.swift on line 12", 12, nil),
        ("Foo.swift at line 12", 12, nil),
        ("Foo.swift:line 12", 12, nil),
        ("Foo.swift(12)", 12, nil),
        ("Foo.swift:(12)", 12, nil),
        ("Foo.swift[12]", 12, nil),
        ("Foo.swift:[12]", 12, nil),
        ("Foo.swift: 5", 5, nil),
        ("Foo.swift:12:5", 12, 5),
        ("Foo.swift:12,5", 12, 5),
        ("Foo.swift 12 5", 12, 5),
        ("Foo.swift(12,5)", 12, 5),
        ("Foo.swift:(12:5)", 12, 5),
        ("Foo.swift[12,5]", 12, 5),
        ("Foo.swift#L12:5", 12, 5),
        ("Foo.swift:12:", 12, nil)
    ] as [(String, Int, Int?)])
    func intelliJLineAndColumnForms(raw: String, line: Int, column: Int?) {
        let parsed = SearchEverywhereQuery.parse(raw)
        #expect(parsed.text == "Foo.swift", "\(raw)")
        #expect(parsed.line == line, "\(raw)")
        #expect(parsed.column == column, "\(raw)")
    }

    @Test func separatorWithoutNumbersStripsTheSuffix() {
        #expect(SearchEverywhereQuery.parse("Foo.swift:") == SearchEverywhereQuery(text: "Foo.swift"))
        #expect(SearchEverywhereQuery.parse("main(") == SearchEverywhereQuery(text: "main"))
        #expect(SearchEverywhereQuery.parse("c#") == SearchEverywhereQuery(text: "c"))
    }

    @Test func zeroLineIsDropped() {
        #expect(SearchEverywhereQuery.parse("Foo.swift:0") == SearchEverywhereQuery(text: "Foo.swift"))
    }

    @Test func zeroColumnIsDropped() {
        #expect(SearchEverywhereQuery.parse("Foo.swift:4:0") == SearchEverywhereQuery(text: "Foo.swift", line: 4))
    }

    @Test func overflowingLineIsDropped() {
        let parsed = SearchEverywhereQuery.parse("Foo.swift:99999999999999999999")
        #expect(parsed == SearchEverywhereQuery(text: "Foo.swift"))
    }

    @Test func multiWordNameKeepsInnerSpaces() {
        #expect(SearchEverywhereQuery.parse("foo bar") == SearchEverywhereQuery(text: "foo bar"))
        #expect(SearchEverywhereQuery.parse("foo bar 7") == SearchEverywhereQuery(text: "foo bar", line: 7))
    }

    @Test func nameStopsAtFirstSeparatorThatLeavesAValidTail() {
        let parsed = SearchEverywhereQuery.parse("a:b.swift:3")
        #expect(parsed == SearchEverywhereQuery(text: "a:b.swift", line: 3))
    }

    @Test func nonLatinNames() {
        let parsed = SearchEverywhereQuery.parse("Ключ.swift:3:4")
        #expect(parsed == SearchEverywhereQuery(text: "Ключ.swift", line: 3, column: 4))
    }

    @Test func multilineTextIsNotSplit() {
        let parsed = SearchEverywhereQuery.parse("foo\nbar:3")
        #expect(parsed == SearchEverywhereQuery(text: "foo\nbar:3"))
    }
}

@Suite("SymbolExtractor")
@MainActor
struct SearchEverywhereSymbolExtractorTests {
    @Test func swiftDeclarations() {
        let source = """
        import Foundation

        @MainActor
        final class WorkspaceController: NSObject {
            private let manager: Manager
            var title: String = ""
            func reload() {}
        }

        struct Point {
            let x: Int
        }

        enum Direction {
            case north
        }

        protocol Reloading {
            func reload()
        }

        extension WorkspaceController {
            func extra() {}
        }

        actor Store {}
        """

        let symbols = SymbolExtractor.symbols(in: source, fileExtension: "swift")
        let byName = Dictionary(grouping: symbols, by: \.name)

        #expect(byName["WorkspaceController"]?.count == 2)
        #expect(byName["WorkspaceController"]?.first?.kind == .classType)
        #expect(byName["WorkspaceController"]?.first?.line == 4)
        #expect(byName["WorkspaceController"]?.last?.kind == .extensionDecl)
        #expect(byName["WorkspaceController"]?.last?.line == 22)

        #expect(byName["manager"]?.first?.kind == .field)
        #expect(byName["manager"]?.first?.line == 5)
        #expect(byName["title"]?.first?.kind == .field)
        #expect(byName["Point"]?.first?.kind == .structType)
        #expect(byName["Point"]?.first?.line == 10)
        #expect(byName["x"]?.first?.line == 11)
        #expect(byName["Direction"]?.first?.kind == .enumType)
        #expect(byName["Reloading"]?.first?.kind == .protocolType)
        #expect(byName["reload"]?.map(\.line) == [7, 19])
        #expect(byName["extra"]?.first?.kind == .method)
        #expect(byName["extra"]?.first?.line == 23)
        #expect(byName["Store"]?.first?.kind == .actorType)
        #expect(byName["Store"]?.first?.line == 26)
        #expect(byName["func"] == nil)
    }

    @Test func typeScriptDeclarations() {
        let source = """
        import { helper } from "./helper"

        export class CartService {
          private items: string[] = []
        }

        export interface Cart {
          id: string
        }

        export type CartID = string

        export function createCart(): Cart {
          return { id: "" }
        }

        export const emptyCart = { items: [] }

        enum Status { Active }
        """

        let symbols = SymbolExtractor.symbols(in: source, fileExtension: "ts")
        let byName = Dictionary(grouping: symbols, by: \.name)

        #expect(byName["CartService"]?.first?.kind == .classType)
        #expect(byName["CartService"]?.first?.line == 3)
        #expect(byName["Cart"]?.first?.kind == .protocolType)
        #expect(byName["Cart"]?.first?.line == 7)
        #expect(byName["CartID"]?.first?.kind == .typeAlias)
        #expect(byName["CartID"]?.first?.line == 11)
        #expect(byName["createCart"]?.first?.kind == .function)
        #expect(byName["createCart"]?.first?.line == 13)
        #expect(byName["emptyCart"]?.first?.kind == .variable)
        #expect(byName["emptyCart"]?.first?.line == 17)
        #expect(byName["Status"]?.first?.kind == .enumType)
        #expect(byName["Status"]?.first?.line == 19)
    }

    @Test func pythonDeclarations() {
        let source = """
        import os

        class Greeter:
            def __init__(self):
                self.name = ""

            async def greet(self):
                return "hi"

        def main():
            pass
        """

        let symbols = SymbolExtractor.symbols(in: source, fileExtension: "py")
        let byName = Dictionary(grouping: symbols, by: \.name)

        #expect(byName["Greeter"]?.first?.kind == .classType)
        #expect(byName["Greeter"]?.first?.line == 3)
        #expect(byName["__init__"]?.first?.kind == .method)
        #expect(byName["__init__"]?.first?.line == 4)
        #expect(byName["greet"]?.first?.kind == .method)
        #expect(byName["greet"]?.first?.line == 7)
        #expect(byName["main"]?.first?.kind == .function)
        #expect(byName["main"]?.first?.line == 10)
    }

    @Test func commentLinesAreIgnored() {
        let source = """
        // class NotASymbol {}
        # class AlsoNotASymbol {}
        final class RealSymbol {}
        """

        let symbols = SymbolExtractor.symbols(in: source, fileExtension: "swift")
        #expect(symbols.map(\.name) == ["RealSymbol"])
        #expect(symbols.first?.line == 3)
    }

    @Test func unknownExtensionYieldsNoSymbols() {
        #expect(SymbolExtractor.symbols(in: "class Foo {}", fileExtension: "xyz").isEmpty)
    }
}
