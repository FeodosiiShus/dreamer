import Foundation
import Testing
@testable import Dreamder

private func symbol(_ name: String, _ kind: SearchEverywhereSymbolKind, _ line: Int) -> ExtractedSymbol {
    ExtractedSymbol(name: name, kind: kind, line: line)
}

private func extract(_ fileExtension: String, _ text: String) -> [ExtractedSymbol] {
    SymbolExtractor.symbols(in: text, fileExtension: fileExtension)
}

@Suite
struct SymbolExtractorSwiftTests {
    @Test
    func typesFunctionsAndMembersOfAnAnnotatedClass() {
        let source = """
        import Foundation

        /// class Documented {}
        @MainActor
        public final class Controller: NSObject {
            private(set) var count = 0
            @Published public private(set) var title = ""
            static let shared = Controller()
            weak var delegate: AnyObject?
            lazy var cache = [String: Int]()
            @discardableResult
            public static func make(_ value: Int) -> Controller { Controller() }
            override func viewDidLoad() {}
            nonisolated func isolated() {}
            func run() {
                let local = 1
                var shadow = 2
            }
            private struct Nested { var deep = 1 }
        }
        """

        #expect(extract("swift", source) == [
            symbol("Controller", .classType, 5),
            symbol("count", .field, 6),
            symbol("title", .field, 7),
            symbol("shared", .field, 8),
            symbol("delegate", .field, 9),
            symbol("cache", .field, 10),
            symbol("make", .method, 12),
            symbol("viewDidLoad", .method, 13),
            symbol("isolated", .method, 14),
            symbol("run", .method, 15),
            symbol("Nested", .structType, 19)
        ])
    }

    @Test
    func everyTypeKeywordMapsToItsKind() {
        let source = """
        struct Point<T> { let x: T }
        public enum Mode { case on }
        indirect enum Tree { case leaf }
        protocol Drawable: AnyObject { func draw() }
        actor Counter {}
        typealias Handler = (Int) -> Void
        open class Base {}
        @available(macOS 26, *) final class Available {}
        @objc(Legacy) nonisolated struct Annotated {}
        package protocol Internal {}
        """

        #expect(extract("swift", source) == [
            symbol("Point", .structType, 1),
            symbol("Mode", .enumType, 2),
            symbol("Tree", .enumType, 3),
            symbol("Drawable", .protocolType, 4),
            symbol("Counter", .actorType, 5),
            symbol("Handler", .typeAlias, 6),
            symbol("Base", .classType, 7),
            symbol("Available", .classType, 8),
            symbol("Annotated", .structType, 9),
            symbol("Internal", .protocolType, 10)
        ])
    }

    @Test
    func extensionsReportTheExtendedTypeName() {
        let source = """
        extension Array where Element: Equatable {}
        public extension String {}
        private extension Foo.Bar: Baz {}
        @MainActor extension Window {}
        """

        #expect(extract("swift", source) == [
            symbol("Array", .extensionDecl, 1),
            symbol("String", .extensionDecl, 2),
            symbol("Foo.Bar", .extensionDecl, 3),
            symbol("Window", .extensionDecl, 4)
        ])
    }

    @Test
    func propertiesCountOnlyAtGlobalOrTypeMemberIndentation() {
        let source = "let global = 3\nvar counter = 0\n    var member = 1\n\tlet tabbed = 2\n        var deep = 3\n\t\tlet deepTabbed = 4"

        #expect(extract("swift", source) == [
            symbol("global", .field, 1),
            symbol("counter", .field, 2),
            symbol("member", .field, 3),
            symbol("tabbed", .field, 4)
        ])
    }

    @Test
    func modifierKeywordsAfterClassAreNotTypeNames() {
        let source = """
        struct Factory {
            class func build() {}
            class var kind: Int { 1 }
            static func == (lhs: Factory, rhs: Factory) -> Bool { true }
            init() {}
            subscript(index: Int) -> Int { index }
            class
        }
        """

        #expect(extract("swift", source) == [
            symbol("Factory", .structType, 1),
            symbol("build", .method, 2),
            symbol("kind", .field, 3)
        ])
    }

    @Test
    func commentsAndConditionalCompilationLinesAreSkipped() {
        let source = """
        // class LineComment {}
        /* struct BlockStart {}
         * enum Continued {}
         */
        #if DEBUG
        class Debug {}
        #endif
        func real() {}
        """

        #expect(extract("swift", source) == [
            symbol("Debug", .classType, 6),
            symbol("real", .method, 8)
        ])
    }

    @Test
    func declarationKeywordsInsideStringLiteralsAddNothingBeyondTheBinding() {
        let source = "let text = \"class Fake { func fake() {} }\"\nlet other = \"struct Nope\""

        #expect(extract("swift", source) == [
            symbol("text", .field, 1),
            symbol("other", .field, 2)
        ])
    }

    @Test
    func crLfLineEndingsKeepLineNumbersAndNames() {
        let source = "struct A {}\r\nfunc f() {}\r\n\r\nclass B {}\r\n"

        #expect(extract("swift", source) == [
            symbol("A", .structType, 1),
            symbol("f", .method, 2),
            symbol("B", .classType, 4)
        ])
    }

    @Test
    func extensionIsCaseInsensitive() {
        #expect(extract("SWIFT", "struct A {}") == [symbol("A", .structType, 1)])
    }
}

@Suite
struct SymbolExtractorJavaScriptTests {
    private static let snippet = """
    export default class Foo extends Bar {}
    export abstract class Abs {}
    declare class Decl {}
    export interface Shape { area(): number }
    export enum Color { Red }
    export type Id = string
    export type Gen<T> = T[]
    type Local = number
    export default async function main() {}
    function* gen() {}
    function  plain(a) {}
    export async function fetchAll() {}
    declare function ambientFn(): void
    const arrow = () => 1
    export const typed: number = 1
    let pending
    var old = 1
    declare const ambient: string
    const { a, b } = obj
    // function commented() {}
    const url = "function fake() {}"
    export default function () {}
    functionCall();
    """

    @Test(arguments: ["ts", "tsx", "js", "jsx", "mjs", "cjs", "TS"])
    func everyScriptExtensionUsesTheScriptExtractor(fileExtension: String) {
        #expect(extract(fileExtension, Self.snippet) == [
            symbol("Foo", .classType, 1),
            symbol("Abs", .classType, 2),
            symbol("Decl", .classType, 3),
            symbol("Shape", .protocolType, 4),
            symbol("Color", .enumType, 5),
            symbol("Id", .typeAlias, 6),
            symbol("Gen", .typeAlias, 7),
            symbol("Local", .typeAlias, 8),
            symbol("main", .function, 9),
            symbol("gen", .function, 10),
            symbol("plain", .function, 11),
            symbol("fetchAll", .function, 12),
            symbol("ambientFn", .function, 13),
            symbol("arrow", .variable, 14),
            symbol("typed", .variable, 15),
            symbol("old", .variable, 17),
            symbol("ambient", .variable, 18),
            symbol("url", .variable, 21)
        ])
    }

    @Test
    func generatorFunctionsAcceptEveryStarSpacing() {
        let source = "function*a() {}\nfunction * b() {}\nfunction *c() {}\nfunction* d() {}"

        #expect(extract("js", source).map(\.name) == ["a", "b", "c", "d"])
    }

    @Test
    func callsThatMerelyStartWithTheWordFunctionAreNotDeclarations() {
        #expect(extract("js", "functionHandler(value)\nfunctional = 1\nfunction real() {}") == [
            symbol("real", .function, 3)
        ])
    }

    @Test
    func genericTypeAliasesAreRecognized() {
        let source = "type Pair<A, B> = [A, B]\nexport type Mapped<T extends object = {}> = { [K in keyof T]: T[K] }"

        #expect(extract("ts", source) == [
            symbol("Pair", .typeAlias, 1),
            symbol("Mapped", .typeAlias, 2)
        ])
    }

    @Test
    func indentedDeclarationsInsideBlocksAreStillListed() {
        let source = "export class Cart {\n  total() {}\n}\nif (ready) {\n  const inner = 1\n}"

        #expect(extract("ts", source) == [
            symbol("Cart", .classType, 1),
            symbol("inner", .variable, 5)
        ])
    }
}

@Suite
struct SymbolExtractorJavaTests {
    @Test
    func classesInterfacesEnumsRecordsAndAnnotationTypes() {
        let source = """
        package demo;
        @Entity
        @Table(name = "accounts")
        public abstract class Account<T> implements Serializable {
            public interface Inner {}
            enum Mode { A }
            record Pair(int a, int b) {}
            public sealed interface Shape permits Circle {}
            non-sealed class Open {}
            @FunctionalInterface interface Fn {}
            public static final class Holder {}
            public @interface Marker {}
            private static strictfp class Strict {}
            // class Commented {}
            void method() {}
            class
        }
        """

        #expect(extract("java", source) == [
            symbol("Account", .classType, 4),
            symbol("Inner", .protocolType, 5),
            symbol("Mode", .enumType, 6),
            symbol("Pair", .classType, 7),
            symbol("Shape", .protocolType, 8),
            symbol("Open", .classType, 9),
            symbol("Fn", .protocolType, 10),
            symbol("Holder", .classType, 11),
            symbol("Marker", .protocolType, 12),
            symbol("Strict", .classType, 13)
        ])
    }

    @Test
    func methodsAndFieldsAreNotListed() {
        #expect(extract("java", "class A {\n    private int count;\n    public void run() {}\n}") == [
            symbol("A", .classType, 1)
        ])
    }

    @Test
    func blockCommentLinesAreSkipped() {
        let source = "/*\n * public class Hidden {}\n */\npublic class Visible {}"

        #expect(extract("java", source) == [symbol("Visible", .classType, 4)])
    }
}

@Suite
struct SymbolExtractorKotlinTests {
    private static let snippet = """
    package demo
    data class User(val id: Int)
    sealed interface Shape
    object Singleton
    companion object Factory
    companion object { }
    enum class Color { RED }
    annotation class Marker
    inline fun <T> map(value: T) = value
    suspend fun fetch() {}
    private fun helper() {}
    fun String.shout() = this
    fun List<String>.joined() = ""
    fun <T> Array<T>.firstOrNone() = 1
    fun String?.orEmpty2() = ""
    fun a.b.Qualified.deep() = 1
    fun Map<String, List<Int>>.nested() = 1
    fun interface Listener { fun on() }
    public fun interface Public
    override fun toString() = ""
    operator fun plus(other: Int) = other
    internal inline fun <reified T> typed() {}
    abstract class Base {
        abstract fun doIt()
        open class Nested
    }
    value class Id(val v: Int)
    // class Commented
    val ignored = 1
    fun main(args: Array<String>) {}
    """

    @Test(arguments: ["kt", "kts"])
    func kotlinDeclarations(fileExtension: String) {
        #expect(extract(fileExtension, Self.snippet) == [
            symbol("User", .classType, 2),
            symbol("Shape", .protocolType, 3),
            symbol("Singleton", .classType, 4),
            symbol("Factory", .classType, 5),
            symbol("Color", .classType, 7),
            symbol("Marker", .classType, 8),
            symbol("map", .function, 9),
            symbol("fetch", .function, 10),
            symbol("helper", .function, 11),
            symbol("shout", .function, 12),
            symbol("joined", .function, 13),
            symbol("firstOrNone", .function, 14),
            symbol("orEmpty2", .function, 15),
            symbol("deep", .function, 16),
            symbol("nested", .function, 17),
            symbol("Listener", .protocolType, 18),
            symbol("Public", .protocolType, 19),
            symbol("toString", .function, 20),
            symbol("plus", .function, 21),
            symbol("typed", .function, 22),
            symbol("Base", .classType, 23),
            symbol("doIt", .function, 24),
            symbol("Nested", .classType, 25),
            symbol("Id", .classType, 27),
            symbol("main", .function, 30)
        ])
    }
}

@Suite
struct SymbolExtractorPythonTests {
    @Test
    func classesAndFunctionsDistinguishedByIndentation() {
        let source = """
        class Greeter(Base):
            def __init__(self): pass
            async def greet(self): pass
            class Inner:
                def deep(self): pass
        def top(): pass
        async def atop(): pass
        # def commented(): pass
        x = "def fake(): pass"
        \tdef tabbed(self): pass
        """

        #expect(extract("py", source) == [
            symbol("Greeter", .classType, 1),
            symbol("__init__", .method, 2),
            symbol("greet", .method, 3),
            symbol("Inner", .classType, 4),
            symbol("deep", .method, 5),
            symbol("top", .function, 6),
            symbol("atop", .function, 7),
            symbol("tabbed", .method, 10)
        ])
    }

    @Test
    func hashCommentedDeclarationsAndPlainAssignmentsYieldNothing() {
        #expect(extract("py", "# class Hidden:\n    # def also_hidden(): pass\nvalue = 1\nclassy = 2").isEmpty)
    }
}

@Suite
struct SymbolExtractorGoTests {
    @Test
    func structsInterfacesFunctionsAndMethods() {
        let source = """
        package main
        type Server struct {}
        type Handler interface {}
        type Alias = int
        type ID int
        func main() {}
        func (s *Server) Start() {}
        func (s Server) Stop() {}
        func (Server) Anon() {}
        func generic[T any](value T) {}
        func (s *Server)NoSpace() {}
        // func commented() {}
            func indented() {}
        """

        #expect(extract("go", source) == [
            symbol("Server", .classType, 2),
            symbol("Handler", .protocolType, 3),
            symbol("main", .function, 6),
            symbol("Start", .method, 7),
            symbol("Stop", .method, 8),
            symbol("Anon", .method, 9),
            symbol("generic", .function, 10),
            symbol("NoSpace", .method, 11),
            symbol("indented", .function, 13)
        ])
    }

    @Test
    func typeDefinitionsOtherThanStructAndInterfaceAreNotListed() {
        #expect(extract("go", "type ID int\ntype Callback func(int)\ntype (\n    Grouped struct{}\n)").isEmpty)
    }
}

@Suite
struct SymbolExtractorRustTests {
    @Test
    func typesAndEveryFunctionQualifierCombination() {
        let source = """
        pub struct Point { x: i32 }
        pub(crate) enum Shape { A }
        pub trait Drawable {}
        unsafe trait Danger {}
        pub unsafe fn raw() {}
        fn private_fn() {}
        pub async fn fetch() {}
        pub const fn constant() {}
        const fn plain_const() {}
        extern "C" fn ffi() {}
        pub extern "C" fn pub_ffi() {}
        pub(in crate::a) fn restricted() {}
        struct Unit;
        // fn commented() {}
        impl Point { fn method(&self) {} }
        type Alias = i32;
        """

        #expect(extract("rs", source) == [
            symbol("Point", .structType, 1),
            symbol("Shape", .enumType, 2),
            symbol("Drawable", .protocolType, 3),
            symbol("Danger", .protocolType, 4),
            symbol("raw", .function, 5),
            symbol("private_fn", .function, 6),
            symbol("fetch", .function, 7),
            symbol("constant", .function, 8),
            symbol("plain_const", .function, 9),
            symbol("ffi", .function, 10),
            symbol("pub_ffi", .function, 11),
            symbol("restricted", .function, 12),
            symbol("Unit", .structType, 13)
        ])
    }
}

@Suite
struct SymbolExtractorMarkdownTests {
    @Test(arguments: ["md", "markdown", "MD"])
    func headingsBecomeNestedFields(fileExtension: String) {
        let source = "# Title\ntext\n## Sub\n### Deep\n# Next"

        #expect(extract(fileExtension, source) == [
            ExtractedSymbol(name: "Title", kind: .field, line: 1, nestingLevel: 0),
            ExtractedSymbol(name: "Sub", kind: .field, line: 3, nestingLevel: 1),
            ExtractedSymbol(name: "Deep", kind: .field, line: 4, nestingLevel: 2),
            ExtractedSymbol(name: "Next", kind: .field, line: 5, nestingLevel: 0)
        ])
    }

    @Test
    func headingsInsideFencedCodeAreNotSymbols() {
        #expect(extract("md", "```\n# not a heading\n```\n# Real").map(\.name) == ["Real"])
    }
}

@Suite
struct SymbolExtractorBoundaryTests {
    @Test(arguments: ["txt", "json", "", "xyz", "c", "html"])
    func unknownExtensionsYieldNothing(fileExtension: String) {
        #expect(extract(fileExtension, "class Foo {}\nfunc bar() {}\n# Heading\ndef baz(): pass").isEmpty)
    }

    @Test(arguments: ["swift", "ts", "tsx", "js", "jsx", "mjs", "cjs", "java", "kt", "kts", "py", "go", "rs", "md"])
    func emptyTextYieldsNothing(fileExtension: String) {
        #expect(extract(fileExtension, "").isEmpty)
    }

    @Test
    func textFileExtensionsListExactlyTheCodeLanguages() {
        #expect(SymbolExtractor.textFileExtensions == [
            "swift", "ts", "tsx", "js", "jsx", "mjs", "cjs", "java", "kt", "kts", "py", "go", "rs"
        ])
    }

    @Test(arguments: [
        (SearchEverywhereSymbolKind.classType, "nodes/class", true),
        (.structType, "nodes/class", true),
        (.actorType, "nodes/class", true),
        (.enumType, "nodes/enum", true),
        (.protocolType, "nodes/interface", true),
        (.typeAlias, "nodes/type", true),
        (.extensionDecl, "nodes/module", false),
        (.method, "nodes/method", false),
        (.function, "nodes/function", false),
        (.field, "nodes/field", false),
        (.variable, "nodes/variable", false)
    ])
    func kindsMapToIconsAndTypeness(kind: SearchEverywhereSymbolKind, icon: String, isType: Bool) {
        #expect(kind.iconName == icon)
        #expect(kind.isType == isType)
    }

    @Test
    func everyKindIsCoveredByTheIconTable() {
        #expect(SearchEverywhereSymbolKind.allCases.count == 11)
    }
}
