import Foundation
import LanguageServerProtocol
import Synchronization
import Testing
@testable import Dreamder

extension LanguageServerDiscoveryTrustTests {
    @Test
    func untrustedWorkspaceNeverResolvesItsOwnBinaryAndReportsOnce() async throws {
        try await withTempDir { directory in
            let workspace = directory.appending(path: "ws").path(percentEncoded: false)
            let local = (workspace as NSString).appendingPathComponent("node_modules/.bin/gopls")
            try makeScript(at: URL(fileURLWithPath: local))
            let recorder = NoticeRecorder()
            let notice = makeNotice(recorder)

            for _ in 0..<2 {
                let binary = await LanguageServerDiscovery.binary(
                    for: .go,
                    workspacePath: workspace,
                    workspaceTrusted: false,
                    registryInstallPath: nil,
                    notice: notice
                )
                #expect(binary?.execPath != local)
                #expect(binary?.env?["PATH"]?.contains(workspace) != true)
            }

            #expect(recorder.snapshot == ["\(workspace)|\(local)"])
        }
    }

    @Test
    func untrustedWorkspaceWithoutLocalServersReportsNothing() async throws {
        try await withTempDir { directory in
            let workspace = directory.path(percentEncoded: false)
            let recorder = NoticeRecorder()

            _ = await LanguageServerDiscovery.binary(
                for: .go,
                workspacePath: workspace,
                workspaceTrusted: false,
                registryInstallPath: nil,
                notice: makeNotice(recorder)
            )

            #expect(recorder.snapshot.isEmpty)
        }
    }

    @Test
    func trustedWorkspaceKeepsUsingItsOwnBinary() async throws {
        try await withTempDir { directory in
            let workspace = directory.appending(path: "ws").path(percentEncoded: false)
            let local = (workspace as NSString).appendingPathComponent("node_modules/.bin/gopls")
            try makeScript(at: URL(fileURLWithPath: local))
            let recorder = NoticeRecorder()

            let binary = await LanguageServerDiscovery.binary(
                for: .go,
                workspacePath: workspace,
                workspaceTrusted: true,
                registryInstallPath: nil,
                notice: makeNotice(recorder)
            )

            #expect(binary?.execPath == local)
            let expectedPathPrefix = (workspace as NSString).appendingPathComponent("node_modules/.bin") + ":"
            #expect(binary?.env?["PATH"]?.hasPrefix(expectedPathPrefix) == true)
            #expect(recorder.snapshot.isEmpty)
        }
    }

    @Test
    func trustedWorkspaceAcceptsALinkThatStaysInsideAndRejectsOneThatEscapes() async throws {
        try await withTempDir { directory in
            let workspaceURL = directory.appending(path: "ws")
            let workspace = workspaceURL.path(percentEncoded: false)
            let local = (workspace as NSString).appendingPathComponent("node_modules/.bin/gopls")
            let package = workspaceURL.appending(path: "node_modules/gopls-pkg/gopls")
            let outside = directory.appending(path: "outside/gopls")
            try makeScript(at: package)
            try makeScript(at: outside)
            try makeLink(at: URL(fileURLWithPath: local), to: package)

            let accepted = await LanguageServerDiscovery.binary(
                for: .go,
                workspacePath: workspace,
                workspaceTrusted: true,
                registryInstallPath: nil
            )
            #expect(accepted?.execPath == local)

            try FileManager.default.removeItem(atPath: local)
            try makeLink(at: URL(fileURLWithPath: local), to: outside)

            let rejected = await LanguageServerDiscovery.binary(
                for: .go,
                workspacePath: workspace,
                workspaceTrusted: true,
                registryInstallPath: nil
            )
            #expect(rejected?.execPath != local)
        }
    }
}
