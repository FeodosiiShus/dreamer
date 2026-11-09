import Foundation
import LanguageServerProtocol
import Synchronization
import Testing
@testable import Dreamder

@Suite("Language server discovery workspace trust")
struct LanguageServerDiscoveryTrustTests {
    final class NoticeRecorder: Sendable {
        let reports = Mutex<[String]>([])

        func record(workspacePath: String, executable: String) {
            reports.withLock { $0.append("\(workspacePath)|\(executable)") }
        }

        var snapshot: [String] {
            reports.withLock { $0 }
        }
    }

    func makeNotice(_ recorder: NoticeRecorder) -> UntrustedWorkspaceServerNotice {
        UntrustedWorkspaceServerNotice { workspacePath, executable in
            recorder.record(workspacePath: workspacePath, executable: executable)
        }
    }

    func makeScript(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path(percentEncoded: false)
        )
    }

    func makeLink(at url: URL, to target: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            atPath: url.path(percentEncoded: false),
            withDestinationPath: target.path(percentEncoded: false)
        )
    }

    @Test
    func untrustedWorkspacesContributeNoProjectLocalDirectories() {
        let untrusted = LanguageServerDiscovery.localSearchPaths(
            workspacePath: "/ws",
            workspaceTrusted: false,
            registryInstallPath: "/reg",
            listDirectory: { _ in ["pkg"] }
        )
        #expect(untrusted == ["/reg", "/reg/pkg/bin", "/reg/pkg/node_modules/.bin", "/reg/pkg/venv/bin"])
        #expect(!untrusted.contains { $0.hasPrefix("/ws") })

        let trusted = LanguageServerDiscovery.localSearchPaths(
            workspacePath: "/ws",
            workspaceTrusted: true,
            registryInstallPath: nil,
            listDirectory: { _ in [] }
        )
        #expect(trusted == ["/ws/node_modules/.bin", "/ws/.venv/bin", "/ws/venv/bin"])
    }

    @Test
    func workspaceSearchPathsNeedANonEmptyRoot() {
        #expect(LanguageServerDiscovery.workspaceSearchPaths(workspacePath: nil).isEmpty)
        #expect(LanguageServerDiscovery.workspaceSearchPaths(workspacePath: "").isEmpty)
        #expect(LanguageServerDiscovery.workspaceSearchPaths(workspacePath: "/ws/") == [
            "/ws/node_modules/.bin", "/ws/.venv/bin", "/ws/venv/bin"
        ])
    }

    @Test
    func containmentFollowsTheResolvedPath() {
        let links = ["/ws/node_modules/.bin/escape": "/elsewhere/server", "/ws/node_modules/.bin/ok": "/ws/pkg/cli.js"]
        let resolve: (String) -> String = { links[$0] ?? $0 }
        func inside(_ path: String, of workspace: String) -> Bool {
            LanguageServerDiscovery.isInsideWorkspace(path, workspacePath: workspace, resolveSymlinks: resolve)
        }

        #expect(inside("/ws/node_modules/.bin/ok", of: "/ws"))
        #expect(!inside("/ws/node_modules/.bin/escape", of: "/ws"))
        #expect(inside("/ws/pkg/cli.js", of: "/ws/"))
        #expect(!inside("/ws-evil/bin/x", of: "/ws"))
    }

    @Test
    func confinementRejectsWorkspaceBinariesThatResolveOutsideTheWorkspace() {
        let links = ["/ws/node_modules/.bin/escape": "/elsewhere/server"]
        let executables: Set<String> = [
            "/ws/node_modules/.bin/escape",
            "/ws/node_modules/.bin/ok",
            "/ws/venv/bin/ok",
            "/usr/bin/global"
        ]
        let check = LanguageServerDiscovery.confinedToWorkspace(
            workspacePath: "/ws",
            isExecutable: { executables.contains($0) },
            resolveSymlinks: { links[$0] ?? $0 }
        )

        #expect(check("/ws/node_modules/.bin/ok"))
        #expect(check("/ws/venv/bin/ok"))
        #expect(!check("/ws/node_modules/.bin/escape"))
        #expect(!check("/ws/node_modules/.bin/missing"))
        #expect(check("/usr/bin/global"))
    }

    @Test
    func confinementWithoutAWorkspaceOnlyChecksExecutability() {
        let check = LanguageServerDiscovery.confinedToWorkspace(
            workspacePath: nil,
            isExecutable: { $0 == "/usr/bin/global" }
        )
        #expect(check("/usr/bin/global"))
        #expect(!check("/usr/bin/other"))
    }

    @Test
    func confinementUsesTheFileSystemResolverByDefault() throws {
        try withTempDir { directory in
            let workspace = directory.appending(path: "ws")
            let inside = workspace.appending(path: "node_modules/pkg/cli")
            let outside = directory.appending(path: "outside/server")
            try makeScript(at: inside)
            try makeScript(at: outside)
            try makeLink(at: workspace.appending(path: "node_modules/.bin/inside"), to: inside)
            try makeLink(at: workspace.appending(path: "node_modules/.bin/outside"), to: outside)

            let check = LanguageServerDiscovery.confinedToWorkspace(
                workspacePath: workspace.path(percentEncoded: false),
                isExecutable: { FileManager.default.isExecutableFile(atPath: $0) }
            )
            #expect(check(workspace.appending(path: "node_modules/.bin/inside").path(percentEncoded: false)))
            #expect(!check(workspace.appending(path: "node_modules/.bin/outside").path(percentEncoded: false)))
        }
    }

    @Test
    func blockedServerIsReportedOnlyWhenTheWorkspaceBinaryWouldHaveWon() {
        let executables: Set<String> = [
            "/ws/node_modules/.bin/typescript-language-server",
            "/ws/node_modules/.bin/vtsls",
            "/usr/bin/typescript-language-server",
            "/usr/bin/gopls"
        ]
        let isExecutable: (String) -> Bool = { executables.contains($0) }

        #expect(LanguageServerDiscovery.blockedWorkspaceServer(
            for: .typescript,
            workspacePath: "/ws",
            searchPaths: ["/usr/bin"],
            isExecutable: isExecutable
        ) == "/ws/node_modules/.bin/typescript-language-server")

        #expect(LanguageServerDiscovery.blockedWorkspaceServer(
            for: .typescript,
            workspacePath: "/ws",
            searchPaths: [],
            isExecutable: { $0 == "/ws/node_modules/.bin/vtsls" }
        ) == "/ws/node_modules/.bin/vtsls")

        #expect(LanguageServerDiscovery.blockedWorkspaceServer(
            for: .typescript,
            workspacePath: "/ws",
            searchPaths: ["/usr/bin"],
            isExecutable: { $0 == "/ws/node_modules/.bin/vtsls" || $0 == "/usr/bin/typescript-language-server" }
        ) == nil)

        #expect(LanguageServerDiscovery.blockedWorkspaceServer(
            for: .go,
            workspacePath: "/ws",
            searchPaths: ["/usr/bin"],
            isExecutable: isExecutable
        ) == nil)

        #expect(LanguageServerDiscovery.blockedWorkspaceServer(
            for: .rust,
            workspacePath: "/ws",
            searchPaths: ["/usr/bin"],
            isExecutable: isExecutable
        ) == nil)

        #expect(LanguageServerDiscovery.blockedWorkspaceServer(
            for: .typescript,
            workspacePath: nil,
            searchPaths: ["/usr/bin"],
            isExecutable: isExecutable
        ) == nil)
    }

    @Test
    func theNoticeReportsOncePerWorkspace() {
        let recorder = NoticeRecorder()
        let notice = makeNotice(recorder)

        notice.note(workspacePath: "/one", executable: "/one/node_modules/.bin/a")
        notice.note(workspacePath: "/one", executable: "/one/node_modules/.bin/b")
        notice.note(workspacePath: "/two", executable: "/two/venv/bin/c")

        #expect(recorder.snapshot == ["/one|/one/node_modules/.bin/a", "/two|/two/venv/bin/c"])
    }

    @Test
    func theLogReportWritesWithoutFailing() {
        UntrustedWorkspaceServerNotice.logReport("/log-once", "/log-once/venv/bin/x")
    }
}
