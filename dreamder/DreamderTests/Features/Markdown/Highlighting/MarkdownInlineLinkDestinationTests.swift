import Foundation
import Testing
@testable import Dreamder

struct MarkdownInlineLinkDestinationTests {
    @Test(arguments: [
        ("[a](b(c)d)", ["b(c)d"]),
        ("[a](x((y))z)", ["x((y))z"]),
        ("[a](b(c)", [])
    ])
    func balancedParenthesesStayInsideTheDestination(text: String, destinations: [String]) {
        #expect(MarkdownLexerSupport.texts(of: .linkDestination, in: text) == destinations)
    }
}
