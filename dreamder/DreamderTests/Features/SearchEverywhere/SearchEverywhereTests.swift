import XCTest
@testable import Dreamder

final class SearchEverywhereMatcherTests: XCTestCase {
    func testRankingExactThenPrefixThenCamelHumpThenSubstring() {
        let exact = SearchEverywhereMatcher.match(query: "ContentView", in: "ContentView")
        let prefix = SearchEverywhereMatcher.match(query: "ContentView", in: "ContentViewDetail")
        let camel = SearchEverywhereMatcher.match(query: "CV", in: "ContentView")
        let substring = SearchEverywhereMatcher.match(query: "ContentView", in: "MyContentViewThing")

        guard let exact, let prefix, let camel, let substring else {
            return XCTFail("Expected all candidates to match")
        }

        XCTAssertGreaterThan(exact.score, prefix.score)
        XCTAssertGreaterThan(prefix.score, camel.score)
        XCTAssertGreaterThan(camel.score, substring.score)
    }

    func testNoMatchForUnrelatedQuery() {
        XCTAssertNil(SearchEverywhereMatcher.match(query: "zzq", in: "ContentView"))
    }

    func testEmptyQueryMatchesEverything() {
        let match = SearchEverywhereMatcher.match(query: "", in: "ContentView")
        XCTAssertEqual(match?.score, 0)
        XCTAssertEqual(match?.ranges, [])
    }

    func testCamelHumpMatchesMultipleWords() {
        let match = SearchEverywhereMatcher.match(query: "DWFM", in: "DreamderWorkspaceFileManager")
        guard let match else {
            return XCTFail("Expected camel hump match")
        }
        XCTAssertEqual(match.ranges, [
            NSRange(location: 0, length: 1),
            NSRange(location: 8, length: 1),
            NSRange(location: 17, length: 1),
            NSRange(location: 21, length: 1)
        ])
    }

    func testCaseInsensitivePrefix() {
        let match = SearchEverywhereMatcher.match(query: "openquick", in: "OpenQuicklyView")
        XCTAssertEqual(match?.score, 900 - (15 / 40))
        XCTAssertEqual(match?.ranges, [NSRange(location: 0, length: 9)])
    }

    func testSubstringHighlightRange() {
        let match = SearchEverywhereMatcher.match(query: "Quickly", in: "MyQuicklyView")
        XCTAssertEqual(match?.ranges, [NSRange(location: 2, length: 7)])
    }
}

final class SearchEverywhereQueryTests: XCTestCase {
    func testPlainQueryHasNoLine() {
        let parsed = SearchEverywhereQuery.parse("ContentView.swift")
        XCTAssertEqual(parsed.text, "ContentView.swift")
        XCTAssertNil(parsed.line)
        XCTAssertNil(parsed.column)
    }

    func testLineSuffix() {
        let parsed = SearchEverywhereQuery.parse("ContentView.swift:42")
        XCTAssertEqual(parsed.text, "ContentView.swift")
        XCTAssertEqual(parsed.line, 42)
        XCTAssertNil(parsed.column)
    }

    func testLineAndColumnSuffix() {
        let parsed = SearchEverywhereQuery.parse("ContentView.swift:42:7")
        XCTAssertEqual(parsed.text, "ContentView.swift")
        XCTAssertEqual(parsed.line, 42)
        XCTAssertEqual(parsed.column, 7)
    }

    func testColonInNameIsKept() {
        let parsed = SearchEverywhereQuery.parse("app:server")
        XCTAssertEqual(parsed.text, "app:server")
        XCTAssertNil(parsed.line)
    }

    func testURLLikeQueryIsUntouched() {
        let parsed = SearchEverywhereQuery.parse("https://example.com")
        XCTAssertEqual(parsed.text, "https://example.com")
        XCTAssertNil(parsed.line)
    }

    func testNumericOnlyQueryIsNotSuffix() {
        let parsed = SearchEverywhereQuery.parse(":42")
        XCTAssertEqual(parsed.text, ":42")
        XCTAssertNil(parsed.line)
    }

    func testTrailingWhitespaceIsTrimmed() {
        let parsed = SearchEverywhereQuery.parse("  App.swift:12  ")
        XCTAssertEqual(parsed.text, "App.swift")
        XCTAssertEqual(parsed.line, 12)
    }
}

final class SearchEverywhereSymbolExtractorTests: XCTestCase {
    func testSwiftDeclarations() {
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

        XCTAssertEqual(byName["WorkspaceController"]?.count, 2)
        XCTAssertEqual(byName["WorkspaceController"]?.first?.kind, .classType)
        XCTAssertEqual(byName["WorkspaceController"]?.first?.line, 4)
        XCTAssertEqual(byName["WorkspaceController"]?.last?.kind, .extensionDecl)
        XCTAssertEqual(byName["WorkspaceController"]?.last?.line, 22)

        XCTAssertEqual(byName["manager"]?.first?.kind, .field)
        XCTAssertEqual(byName["manager"]?.first?.line, 5)
        XCTAssertEqual(byName["title"]?.first?.kind, .field)
        XCTAssertEqual(byName["Point"]?.first?.kind, .structType)
        XCTAssertEqual(byName["Point"]?.first?.line, 10)
        XCTAssertEqual(byName["x"]?.first?.line, 11)
        XCTAssertEqual(byName["Direction"]?.first?.kind, .enumType)
        XCTAssertEqual(byName["Reloading"]?.first?.kind, .protocolType)
        XCTAssertEqual(byName["reload"]?.map(\.line), [7, 19])
        XCTAssertEqual(byName["extra"]?.first?.kind, .method)
        XCTAssertEqual(byName["extra"]?.first?.line, 23)
        XCTAssertEqual(byName["Store"]?.first?.kind, .actorType)
        XCTAssertEqual(byName["Store"]?.first?.line, 26)
        XCTAssertNil(byName["func"])
    }

    func testTypeScriptDeclarations() {
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

        XCTAssertEqual(byName["CartService"]?.first?.kind, .classType)
        XCTAssertEqual(byName["CartService"]?.first?.line, 3)
        XCTAssertEqual(byName["Cart"]?.first?.kind, .protocolType)
        XCTAssertEqual(byName["Cart"]?.first?.line, 7)
        XCTAssertEqual(byName["CartID"]?.first?.kind, .typeAlias)
        XCTAssertEqual(byName["CartID"]?.first?.line, 11)
        XCTAssertEqual(byName["createCart"]?.first?.kind, .function)
        XCTAssertEqual(byName["createCart"]?.first?.line, 13)
        XCTAssertEqual(byName["emptyCart"]?.first?.kind, .variable)
        XCTAssertEqual(byName["emptyCart"]?.first?.line, 17)
        XCTAssertEqual(byName["Status"]?.first?.kind, .enumType)
        XCTAssertEqual(byName["Status"]?.first?.line, 19)
    }

    func testPythonDeclarations() {
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

        XCTAssertEqual(byName["Greeter"]?.first?.kind, .classType)
        XCTAssertEqual(byName["Greeter"]?.first?.line, 3)
        XCTAssertEqual(byName["__init__"]?.first?.kind, .method)
        XCTAssertEqual(byName["__init__"]?.first?.line, 4)
        XCTAssertEqual(byName["greet"]?.first?.kind, .method)
        XCTAssertEqual(byName["greet"]?.first?.line, 7)
        XCTAssertEqual(byName["main"]?.first?.kind, .function)
        XCTAssertEqual(byName["main"]?.first?.line, 10)
    }

    func testCommentLinesAreIgnored() {
        let source = """
        // class NotASymbol {}
        # class AlsoNotASymbol {}
        final class RealSymbol {}
        """

        let symbols = SymbolExtractor.symbols(in: source, fileExtension: "swift")
        XCTAssertEqual(symbols.map(\.name), ["RealSymbol"])
        XCTAssertEqual(symbols.first?.line, 3)
    }

    func testUnknownExtensionYieldsNoSymbols() {
        XCTAssertTrue(SymbolExtractor.symbols(in: "class Foo {}", fileExtension: "xyz").isEmpty)
    }
}
