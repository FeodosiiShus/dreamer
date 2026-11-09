import AppKit
import Foundation
import Testing
@testable import Dreamder

extension ProjectNavigatorReplaceSafetyTests {
    private static let willRenameOnly = ["willRenameFiles old=exists new=missing"]
    private static let willAndDidRename = [
        "willRenameFiles old=exists new=missing",
        "didRenameFiles old=missing new=exists"
    ]

    private func registerRenameClient(
        in harness: Harness,
        source: URL,
        destination: URL
    ) async throws -> RenameOrderObservingConnection {
        let rename = RenameFileOperationsTests()
        let connection = RenameOrderObservingConnection(
            inner: ScriptedServerConnection(),
            old: source,
            new: destination
        )
        let client = try await rename.makeClient(
            root: harness.root,
            connection: connection,
            capabilities: rename.capabilities(will: rename.filters("**/*.ts"), did: rename.filters("**/*.ts"))
        )
        LSPService.shared.languageClients[LSPService.ClientKey(.swift, harness.root.path())] = client
        return connection
    }

    private func unregisterRenameClient(in harness: Harness) {
        LSPService.shared.languageClients[LSPService.ClientKey(.swift, harness.root.path())] = nil
    }

    @Test
    func aReplacingMoveSendsTheRenameHooksExactlyOnceAfterSettingTheDestinationAside() async throws {
        let files = ["Incoming/item.ts", "Library/item.ts"]
        try await Harness.run(folders: ["Incoming", "Library"], files: files) { harness in
            let source = harness.url("Incoming/item.ts")
            let connection = try await registerRenameClient(
                in: harness,
                source: source,
                destination: harness.url("Library/item.ts")
            )
            defer { unregisterRenameClient(in: harness) }
            harness.controller.confirmReplace = { _ in true }

            let accepted = harness.acceptDrop(harness.dropInfo(urls: [source]), onto: try harness.file("Library"))

            #expect(accepted)
            try await eventually(timeout: .seconds(20)) {
                connection.observations.count == 2 && (try? harness.names(in: "Library")) == ["item.ts"]
            }
            #expect(connection.observations == Self.willAndDidRename)
            #expect(try harness.contents("Library/item.ts") == "content of Incoming/item.ts\n")
            #expect(!harness.exists("Incoming/item.ts"))
        }
    }

    @Test
    func aFailingReplacingMoveRestoresTheDestinationAndNeverSendsDidRename() async throws {
        let files = ["Incoming/item.ts", "Library/item.ts"]
        try await Harness.run(folders: ["Incoming", "Library"], files: files) { harness in
            let source = harness.url("Incoming/item.ts")
            let connection = try await registerRenameClient(
                in: harness,
                source: source,
                destination: harness.url("Library/item.ts")
            )
            defer { unregisterRenameClient(in: harness) }
            harness.controller.confirmReplace = { _ in true }
            try harness.failTransfers(with: marker("replacing move failure")) { from, target in
                from.lastPathComponent == "item.ts" && target.lastPathComponent == "item.ts"
            }

            _ = harness.acceptDrop(harness.dropInfo(urls: [source]), onto: try harness.file("Library"))

            try await eventually(timeout: .seconds(20)) {
                (try? harness.contents("Library/item.ts")) == "content of Library/item.ts\n"
                    && (try? harness.names(in: "Library")) == ["item.ts"]
            }
            #expect(connection.observations == Self.willRenameOnly)
            #expect(try harness.contents("Incoming/item.ts") == "content of Incoming/item.ts\n")
        }
    }
}
