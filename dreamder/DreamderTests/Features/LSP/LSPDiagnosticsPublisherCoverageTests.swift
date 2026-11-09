import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

struct LSPDiagnosticsPathContainmentTests {
    @Test
    func aPathIsWithinItsRootAndEverythingBelowIt() {
        #expect(LSPDiagnosticsPublisher.isPath("/work/app", within: "/work/app"))
        #expect(LSPDiagnosticsPublisher.isPath("/work/app/Sources/main.swift", within: "/work/app"))
    }

    @Test
    func aSiblingWithTheSamePrefixIsNotWithinTheRoot() {
        #expect(!LSPDiagnosticsPublisher.isPath("/work/app-tools/main.swift", within: "/work/app"))
        #expect(!LSPDiagnosticsPublisher.isPath("/work", within: "/work/app"))
    }

    @Test
    func theFilesystemRootContainsEveryAbsolutePath() {
        #expect(LSPDiagnosticsPublisher.isPath("/work/app/main.swift", within: "/"))
        #expect(LSPDiagnosticsPublisher.isPath("/", within: "/"))
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct LSPDiagnosticsWorkspaceLookupTests {
    @Test
    func theWorkspaceOwningAFileIsFoundByItsRootOrAnyPathBelowIt() throws {
        try withTempDir { directory in
            let workspace = try HostedSourceEditorFixture.registerWorkspace(at: directory)
            defer { workspace.close() }

            #expect(LSPDiagnosticsPublisher.workspace(containing: directory) === workspace)
            #expect(LSPDiagnosticsPublisher.workspace(containing: directory.appending(path: "Sources/main.swift")) === workspace)
            #expect(LSPDiagnosticsPublisher.workspace(containing: URL(fileURLWithPath: "/nonexistent/dreamder/other.swift")) == nil)
        }
    }

    @Test
    func anExplicitWorkspacePathWinsOverTheContainingRoot() throws {
        try withTempDir { directory in
            let workspace = try HostedSourceEditorFixture.registerWorkspace(at: directory)
            defer { workspace.close() }

            let found = LSPDiagnosticsPublisher.workspace(
                containing: URL(fileURLWithPath: "/nonexistent/dreamder/other.swift"),
                workspacePath: directory.path(percentEncoded: false)
            )

            #expect(found === workspace)
        }
    }

    @Test
    func clearingDiagnosticsOfAnUntrackedOrForeignDocumentLeavesTheStoreAlone() throws {
        try withTempDir { directory in
            let workspace = try HostedSourceEditorFixture.registerWorkspace(at: directory)
            defer { workspace.close() }
            let tracked = directory.appending(path: "tracked.swift")
            let diagnostic = WorkspaceDiagnostic(
                fileURL: tracked, startLine: 1, startColumn: 1, endLine: 1, endColumn: 2,
                severity: .error, message: "boom", source: nil, code: nil
            )
            workspace.diagnosticsStore.replace([diagnostic], for: tracked)

            LSPDiagnosticsPublisher.clear("untitled:Scratch")
            LSPDiagnosticsPublisher.clear("file:///nonexistent/dreamder/other.swift")

            #expect(workspace.diagnosticsStore.diagnostics(for: tracked).map(\.message) == ["boom"])

            LSPDiagnosticsPublisher.clear(tracked.lspURI)

            #expect(workspace.diagnosticsStore.diagnostics(for: tracked).isEmpty)
        }
    }

    @Test
    func publishingToAnUntrackedOrForeignDocumentLeavesTheStoreAlone() throws {
        try withTempDir { directory in
            let workspace = try HostedSourceEditorFixture.registerWorkspace(at: directory)
            defer { workspace.close() }
            let tracked = directory.appending(path: "tracked.swift")
            let diagnostic = Diagnostic(
                range: SyncTestServer.range(0, 0, 3),
                severity: .warning,
                source: "test",
                message: "careful"
            )

            LSPDiagnosticsPublisher.publish([diagnostic], forDocument: "untitled:Scratch")
            LSPDiagnosticsPublisher.publish([diagnostic], forDocument: "file:///nonexistent/dreamder/other.swift")

            #expect(workspace.diagnosticsStore.diagnostics(for: tracked).isEmpty)

            LSPDiagnosticsPublisher.publish([diagnostic], forDocument: tracked.lspURI)

            #expect(workspace.diagnosticsStore.diagnostics(for: tracked).map(\.message) == ["careful"])
        }
    }
}
