import Foundation
import LanguageClient
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite("LanguageServer local process", .uiGate)
struct LanguageServerLocalProcessTests {
    typealias Server = LanguageServer<CodeFileDocument>

    private static let cannedInitializeServer = """
    IFS= read -r header
    length=$(printf '%s' "$header" | tr -dc '0-9')
    IFS= read -r blank
    body=$(dd bs=1 count="$length" 2>/dev/null)
    id=$(printf '%s' "$body" | sed 's/.*"id":\\([^,}]*\\).*/\\1/')
    response="{\\"jsonrpc\\":\\"2.0\\",\\"id\\":$id,\\"result\\":{\\"capabilities\\":{}}}"
    printf 'Content-Length: %d\\r\\n\\r\\n%s' "${#response}" "$response"
    exec cat > /dev/null
    """

    private let language = LSPLanguage(rawValue: "ruby")

    @Test func createServerInitializesOverARealProcessAndReportsItsTermination() async throws {
        let binary = LanguageServerBinary(
            execPath: "/bin/sh",
            args: ["-c", Self.cannedInitializeServer],
            env: ["PATH": "/usr/bin:/bin"]
        )
        let language = language
        let server = try await withTimeout(duration: .seconds(60)) {
            try await Server.createServer(for: language, with: binary, workspacePath: "/tmp")
        }

        let pid = try #require(server.pid > 0 ? server.pid : nil)
        #expect(server.languageId == language)
        #expect(server.binary.execPath == "/bin/sh")
        #expect(server.serverInfo == nil)

        let terminations = server.terminationEvents
        kill(pid, SIGTERM)
        let fired = try await withTimeout(duration: .seconds(60)) {
            for await _ in terminations {
                return true
            }
            return false
        }
        #expect(fired)
        try await eventually {
            server.logContainer.logs.contains { $0.message == "Data Channel Terminated Unexpectedly" }
        }
    }

    @Test func anUnreachableBinaryFailsToCreateAConnection() {
        var failed = false
        do {
            _ = try Server.makeLocalServerConnection(
                languageId: language,
                executionParams: Process.ExecutionParameters(
                    path: "/nonexistent/dreamder-language-server",
                    arguments: [],
                    environment: nil
                ),
                logContainer: LanguageServerLogContainer(languageID: language.rawValue),
                onTermination: {}
            )
        } catch {
            failed = true
        }
        #expect(failed)
    }
}
