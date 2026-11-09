import Foundation
import Testing
@testable import Dreamder

@Suite("UntrustedWorkspaceServerPolicy")
struct UntrustedWorkspaceServerPolicyTests {
    static let typeScriptRawValues: Set<String> = ["typescript", "javascript", "typescriptreact", "javascriptreact"]

    static let pinnedServer = "/opt/node/bin/typescript-language-server"
    static let unpinnedServer = "/opt/node/bin/vtsls"

    static let deniedExamples: [LSPLanguage] = [
        .swift, .objc, .objcpp, .c, .cpp, .python, .go, .rust, .json, .css, .scss, .less, .html, .java, .yaml,
        .shellscript, .kotlin, .toml, LSPLanguage(rawValue: "ruby")
    ]

    @Test(arguments: LSPLanguage.known)
    func onlyTypeScriptLanguagesWithTheTypeScriptLanguageServerArePermittedUntrusted(language: LSPLanguage) {
        let permitted = Self.typeScriptRawValues.contains(language.rawValue)

        #expect(UntrustedWorkspaceServerPolicy.permitsServer(
            for: language, executable: Self.pinnedServer, workspaceTrusted: false
        ) == permitted)
    }

    @Test(arguments: LSPLanguage.known + [LSPLanguage(rawValue: "ruby")])
    func aTrustedWorkspacePermitsEveryServer(language: LSPLanguage) {
        for executable in [Self.pinnedServer, Self.unpinnedServer, "/usr/bin/other"] {
            #expect(UntrustedWorkspaceServerPolicy.permitsServer(
                for: language, executable: executable, workspaceTrusted: true
            ))
        }
    }

    @Test(arguments: [LSPLanguage.typescript, .javascript, .typescriptreact, .javascriptreact])
    func vtslsIsDeniedUntrustedBecauseItIgnoresThePinnedTypeScript(language: LSPLanguage) {
        #expect(!UntrustedWorkspaceServerPolicy.permitsServer(
            for: language, executable: Self.unpinnedServer, workspaceTrusted: false
        ))
        #expect(!UntrustedWorkspaceServerPolicy.permitsServer(
            for: language, executable: "typescript-language-server-wrapper", workspaceTrusted: false
        ))
    }

    @Test(arguments: deniedExamples)
    func everyOtherFamilyIsDeniedUntrustedWhateverTheExecutable(language: LSPLanguage) {
        for executable in [Self.pinnedServer, Self.unpinnedServer] {
            #expect(!UntrustedWorkspaceServerPolicy.permitsServer(
                for: language, executable: executable, workspaceTrusted: false
            ))
        }
    }

    @Test
    func theAllowlistIsExactlyTheTypeScriptLanguageServer() {
        #expect(UntrustedWorkspaceServerPolicy.permittedServers == [.typescript: ["typescript-language-server"]])
        #expect(LSPLanguage.known.filter { $0.serverFamily == .typescript }.map(\.rawValue).sorted()
            == Self.typeScriptRawValues.sorted())
    }

    @Test
    func theFailureMessageNamesTheSkippedExecutableWithoutItsDirectory() {
        let expected = "Safe Mode: the rust-analyzer language server was not started. Trust the project to use it."

        #expect(UntrustedWorkspaceServerPolicy.failureMessage(forExecutable: "/opt/bin/rust-analyzer") == expected)
        #expect(UntrustedWorkspaceServerPolicy.failureMessage(forExecutable: "rust-analyzer") == expected)
    }

    @Test
    func theErrorIdentifiesTheDeniedLanguage() {
        #expect(UntrustedWorkspaceServerError(language: .go) == UntrustedWorkspaceServerError(language: .go))
        #expect(UntrustedWorkspaceServerError(language: .go) != UntrustedWorkspaceServerError(language: .rust))
    }
}
