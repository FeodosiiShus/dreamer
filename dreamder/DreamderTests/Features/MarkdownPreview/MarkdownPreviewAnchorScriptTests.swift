import Foundation
import JavaScriptCore
import Testing
@testable import Dreamder

@Suite
struct MarkdownPreviewAnchorScriptTests {
    private static let environment = """
    var window = this;
    var elements = {};
    var scrolled = [];
    function register(id) {
      elements[id] = { scrollIntoView: function () { scrolled.push(id); } };
    }
    var document = {
      body: null,
      getElementById: function (id) { return elements.hasOwnProperty(id) ? elements[id] : null; }
    };
    """

    private func makeContext(registering identifiers: [String]) throws -> JSContext {
        let context = try #require(JSContext())
        context.exceptionHandler = { _, exception in
            Issue.record("JavaScript exception: \(exception?.toString() ?? "unknown")")
        }
        context.evaluateScript(Self.environment)
        for identifier in identifiers {
            context.evaluateScript("register(\"\(identifier)\");")
        }
        context.evaluateScript(MarkdownPreviewScripts.pageScript)
        return context
    }

    private func scrolled(after anchor: String, registering identifiers: [String]) throws -> String {
        let context = try makeContext(registering: identifiers)
        context.evaluateScript("window.dreamderPreview.scrollToAnchor(\"\(anchor)\");")
        return try #require(context.evaluateScript("JSON.stringify(scrolled)")?.toString())
    }

    @Test
    func generatedIdentifiersScrollDirectly() throws {
        #expect(try scrolled(after: "intro", registering: ["intro"]) == "[\"intro\"]")
    }

    @Test
    func rawHTMLIdentifiersAreFoundThroughTheirNamespace() throws {
        let prefix = MarkdownHTMLSanitizer.userIdentifierPrefix
        #expect(try scrolled(after: "custom", registering: ["\(prefix)custom"]) == "[\"\(prefix)custom\"]")
    }

    @Test
    func generatedIdentifiersWinOverRawHTMLIdentifiers() throws {
        let prefix = MarkdownHTMLSanitizer.userIdentifierPrefix
        #expect(try scrolled(after: "same", registering: ["\(prefix)same", "same"]) == "[\"same\"]")
    }

    @Test
    func unknownAnchorsDoNothing() throws {
        #expect(try scrolled(after: "missing", registering: ["intro"]) == "[]")
    }

    @Test
    func theEntryPointIsInstalledByThePageScript() throws {
        let context = try makeContext(registering: [])
        #expect(context.evaluateScript("typeof window.dreamderPreview.replaceBody")?.toString() == "function")
        #expect(context.evaluateScript("typeof window.dreamderPreview.scrollToAnchor")?.toString() == "function")
    }
}
