import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite("URL.lspURI", .serialized, .uiGate)
struct LSPDocumentURITests {
    nonisolated static let cases: [(path: String, uri: String)] = [
        ("/tmp/plain.ts", "file:///tmp/plain.ts"),
        ("/tmp/a b.ts", "file:///tmp/a%20b.ts"),
        ("/tmp/a#b.ts", "file:///tmp/a%23b.ts"),
        ("/tmp/what?.ts", "file:///tmp/what%3F.ts"),
        ("/tmp/100%.md", "file:///tmp/100%25.md"),
        ("/tmp/100%25.md", "file:///tmp/100%2525.md"),
        ("/tmp/a b#c%.ts", "file:///tmp/a%20b%23c%25.ts"),
        ("/tmp/日本/本.ts", "file:///tmp/%E6%97%A5%E6%9C%AC/%E6%9C%AC.ts"),
        ("/Users/me/My Project #1/src/main.rs", "file:///Users/me/My%20Project%20%231/src/main.rs")
    ]

    @Test(arguments: cases)
    func theURIIsPercentEncoded(path: String, uri: String) {
        #expect(URL(fileURLWithPath: path).lspURI == uri)
    }

    @Test(arguments: cases)
    func theURIRoundTripsThroughTheServerSideDecoders(path: String, uri: String) throws {
        let url = URL(fileURLWithPath: path)

        #expect(LSPFileURI.fileURL(from: url.lspURI)?.path(percentEncoded: false) == path)
        #expect(LSPDiagnosticMapping.fileURL(fromDocumentURI: url.lspURI)?.path(percentEncoded: false) == path)
        let fromServer = try #require(URL(string: uri))
        #expect(fromServer.absolutePath == path)
        #expect(fromServer.lspURI == uri)
    }

    @Test(arguments: cases)
    func theWorkspaceKeySpellingStaysUnencoded(path: String, uri: String) {
        #expect(URL(fileURLWithPath: path).absolutePath == path)
    }

    @Test
    func aURIFromAServerAndADocumentURLAddressTheSameFile() throws {
        let serverURI = "file:///Users/me/My%20Project%20%231/a%3Fb%25.ts"
        let fromServer = try #require(LSPFileURI.fileURL(from: serverURI))

        #expect(fromServer.lspURI == serverURI)
        #expect(URL(fileURLWithPath: "/Users/me/My Project #1/a?b%.ts").lspURI == serverURI)
    }

    nonisolated static let precomposedPath = "/tmp/h\u{E9}llo.ts"
    nonisolated static let decomposedPath = "/tmp/he\u{301}llo.ts"
    nonisolated static let decomposedURI = "file:///tmp/he%CC%81llo.ts"
    nonisolated static let precomposedServerURI = "file:///tmp/h%C3%A9llo.ts"

    @Test(arguments: [precomposedPath, decomposedPath])
    func theURIOfOneFileIsTheDecomposedFormWhateverTheSpellingOfItsPath(path: String) {
        #expect(URL(fileURLWithPath: path).lspURI == Self.decomposedURI)
    }

    @Test(arguments: [precomposedServerURI, decomposedURI])
    func aServerURIInEitherNormalisationMapsToTheSameDocumentURI(serverURI: String) throws {
        let fromServer = try #require(LSPFileURI.fileURL(from: serverURI))

        #expect(fromServer.lspURI == Self.decomposedURI)
        #expect(fromServer.path(percentEncoded: false) == Self.precomposedPath)
        #expect(try #require(URL(string: serverURI)).lspURI == Self.decomposedURI)
    }
}
