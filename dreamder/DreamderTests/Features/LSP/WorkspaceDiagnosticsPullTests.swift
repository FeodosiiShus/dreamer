import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

private func pullTestDiagnostic(line: Int = 1, message: String = "boom") -> Diagnostic {
    Diagnostic(
        range: LSPRange(start: Position(line: line, character: 2), end: Position(line: line, character: 5)),
        severity: .error,
        code: nil,
        source: "tsc",
        message: message
    )
}

@Suite("Workspace diagnostics models")
struct WorkspaceDiagnosticsModelTests {
    private func decodeAny(_ json: String) throws -> LSPAny {
        try JSONDecoder().decode(LSPAny.self, from: Data(json.utf8))
    }

    @Test func paramsOmitTheIdentifierWhenAbsentAndListPreviousResultIds() throws {
        let bare = try WorkspaceDiagnosticParams(identifier: nil, previousResultIds: []).lspAny()
        #expect(bare == .hash(["previousResultIds": .array([])]))

        let full = try WorkspaceDiagnosticParams(
            identifier: "ws",
            previousResultIds: [.init(uri: "file:///a.ts", value: "r1")]
        ).lspAny()
        #expect(full == .hash([
            "identifier": .string("ws"),
            "previousResultIds": .array([.hash(["uri": .string("file:///a.ts"), "value": .string("r1")])])
        ]))
    }

    @Test func decodesFullAndUnchangedItemsIncludingNullVersions() throws {
        let any = try decodeAny("""
        {"items":[
          {"kind":"full","uri":"file:///a.ts","version":null,"resultId":"r1","items":[
            {"range":{"start":{"line":1,"character":2},"end":{"line":1,"character":5}},
             "severity":2,"source":"tsc","message":"careful"}
          ]},
          {"kind":"unchanged","uri":"file:///b.ts","version":3,"resultId":"r2"}
        ]}
        """)
        let report = try WorkspaceDiagnosticReport.decode(any)

        #expect(report.items.map(\.kind) == [.full, .unchanged])
        #expect(report.items[0].version == nil)
        #expect(report.items[0].resultId == "r1")
        #expect(report.items[0].items?.first?.message == "careful")
        #expect(report.items[0].items?.first?.severity == .warning)
        #expect(report.items[1].version == 3)
        #expect(report.items[1].items == nil)
    }

    @Test func rejectsPayloadsWithoutItems() throws {
        #expect(throws: (any Error).self) { try WorkspaceDiagnosticReport.decode(.null) }
    }

    @Test func fullReportsRecordResultIdsAndPublishEveryItem() {
        var state = WorkspaceDiagnosticsPullState()
        let publications = state.apply(WorkspaceDiagnosticReport(items: [
            WorkspaceDocumentDiagnosticReport(
                kind: .full, uri: "file:///b.ts", version: nil, resultId: "rb", items: [pullTestDiagnostic()]
            ),
            WorkspaceDocumentDiagnosticReport(kind: .full, uri: "file:///a.ts", version: 1, resultId: "ra", items: nil)
        ]))

        #expect(publications == [
            WorkspaceDiagnosticPublication(uri: "file:///b.ts", diagnostics: [pullTestDiagnostic()]),
            WorkspaceDiagnosticPublication(uri: "file:///a.ts", diagnostics: [])
        ])
        #expect(state.params(identifier: "x") == WorkspaceDiagnosticParams(
            identifier: "x",
            previousResultIds: [
                .init(uri: "file:///a.ts", value: "ra"),
                .init(uri: "file:///b.ts", value: "rb")
            ]
        ))
    }

    @Test func unchangedReportsKeepTheStoreAndRecordTheNewResultId() {
        var state = WorkspaceDiagnosticsPullState()
        _ = state.apply(WorkspaceDiagnosticReport(items: [
            WorkspaceDocumentDiagnosticReport(kind: .full, uri: "file:///a.ts", version: nil, resultId: "r1", items: [])
        ]))
        let publications = state.apply(WorkspaceDiagnosticReport(items: [
            WorkspaceDocumentDiagnosticReport(kind: .unchanged, uri: "file:///a.ts", version: nil, resultId: "r2", items: nil),
            WorkspaceDocumentDiagnosticReport(kind: .unchanged, uri: "file:///c.ts", version: nil, resultId: nil, items: nil)
        ]))

        #expect(publications.isEmpty)
        #expect(state.resultIds == ["file:///a.ts": "r2"])
    }

    @Test func fullReportsWithoutResultIdForgetThePreviousOne() {
        var state = WorkspaceDiagnosticsPullState()
        _ = state.apply(WorkspaceDiagnosticReport(items: [
            WorkspaceDocumentDiagnosticReport(kind: .full, uri: "file:///a.ts", version: nil, resultId: "r1", items: [])
        ]))
        _ = state.apply(WorkspaceDiagnosticReport(items: [
            WorkspaceDocumentDiagnosticReport(kind: .full, uri: "file:///a.ts", version: nil, resultId: nil, items: [])
        ]))
        #expect(state.resultIds.isEmpty)

        _ = state.apply(WorkspaceDiagnosticReport(items: [
            WorkspaceDocumentDiagnosticReport(kind: .full, uri: "file:///a.ts", version: nil, resultId: "r3", items: [])
        ]))
        state.reset()
        #expect(state.resultIds.isEmpty)
    }

    @Test func supportComesFromStaticOptionsFirstAndThenDynamicRegistrations() {
        let staticA = TwoTypeOption<DiagnosticOptions, DiagnosticRegistrationOptions>.optionA(
            DiagnosticOptions(identifier: "a", interFileDependencies: false, workspaceDiagnostics: true)
        )
        let staticB = TwoTypeOption<DiagnosticOptions, DiagnosticRegistrationOptions>.optionB(
            DiagnosticRegistrationOptions(identifier: "b", interFileDependencies: false, workspaceDiagnostics: true)
        )
        let withoutWorkspace = TwoTypeOption<DiagnosticOptions, DiagnosticRegistrationOptions>.optionA(
            DiagnosticOptions(identifier: "n", interFileDependencies: false, workspaceDiagnostics: false)
        )
        let withoutWorkspaceB = TwoTypeOption<DiagnosticOptions, DiagnosticRegistrationOptions>.optionB(
            DiagnosticRegistrationOptions(identifier: "n", interFileDependencies: false, workspaceDiagnostics: false)
        )
        let dynamic = [
            DiagnosticRegistrationOptions(identifier: "off", interFileDependencies: false, workspaceDiagnostics: false),
            DiagnosticRegistrationOptions(identifier: "on", interFileDependencies: false, workspaceDiagnostics: true)
        ]

        #expect(WorkspaceDiagnosticsSupport.resolve(static: staticA, dynamic: dynamic)?.identifier == "a")
        #expect(WorkspaceDiagnosticsSupport.resolve(static: staticB, dynamic: [])?.identifier == "b")
        #expect(WorkspaceDiagnosticsSupport.resolve(static: withoutWorkspace, dynamic: dynamic)?.identifier == "on")
        #expect(WorkspaceDiagnosticsSupport.resolve(static: withoutWorkspaceB, dynamic: [])?.identifier == nil)
        #expect(WorkspaceDiagnosticsSupport.resolve(static: withoutWorkspaceB, dynamic: []) == nil)
        #expect(WorkspaceDiagnosticsSupport.resolve(static: nil, dynamic: dynamic)?.identifier == "on")
        #expect(WorkspaceDiagnosticsSupport.resolve(static: nil, dynamic: []) == nil)
    }
}

@MainActor
@Suite("Workspace diagnostics pull", .uiGate)
struct WorkspaceDiagnosticsPullTests {
    let fixture = LSPServiceFixture()

    private func workspaceRequests(of connection: ScriptedServerConnection) -> [LSPAny] {
        connection.requests.compactMap { request in
            guard case let .custom(method, params, _) = request, method == "workspace/diagnostic" else { return nil }
            return params
        }
    }

    private func fullReport(_ uri: String, resultId: String, items: [Diagnostic]) -> WorkspaceDiagnosticReport {
        WorkspaceDiagnosticReport(items: [
            WorkspaceDocumentDiagnosticReport(kind: .full, uri: uri, version: nil, resultId: resultId, items: items)
        ])
    }

    private func unchangedReport(_ uri: String, resultId: String) -> WorkspaceDiagnosticReport {
        WorkspaceDiagnosticReport(items: [
            WorkspaceDocumentDiagnosticReport(kind: .unchanged, uri: uri, version: nil, resultId: resultId, items: nil)
        ])
    }

    private func enableWorkspaceDiagnostics(identifier: String? = "ws") {
        fixture.capabilities.diagnosticProvider = .optionA(
            DiagnosticOptions(identifier: identifier, interFileDependencies: true, workspaceDiagnostics: true)
        )
    }

    @Test func fullReportPublishesAndUnchangedKeepsTheStoreWithThePreviousResultId() async throws {
        try await withTempDir { dir in
            enableWorkspaceDiagnostics()
            let service = fixture.makeService()
            let workspace = try LSPServiceWorkspace(directory: dir, files: ["a.ts": "let a = 1\n"])
            defer { workspace.close() }
            let server = try await service.startServer(for: .typescript, workspacePath: workspace.path)
            let connection = try #require(fixture.created.first).connection
            let key = workspace.key(.typescript)
            let uri = workspace.uri("a.ts")
            let fileURL = dir.appending(path: "a.ts")
            let puller = WorkspaceDiagnosticsPuller()

            try connection.script(.custom, fullReport(uri, resultId: "r1", items: [pullTestDiagnostic()]))
            #expect(await puller.pull(client: server, key: key))
            #expect(workspace.workspace.diagnosticsStore.diagnostics(for: fileURL).map(\.message) == ["boom"])

            try connection.script(.custom, unchangedReport(uri, resultId: "r2"))
            #expect(await puller.pull(client: server, key: key))
            #expect(workspace.workspace.diagnosticsStore.diagnostics(for: fileURL).map(\.message) == ["boom"])

            try connection.script(.custom, unchangedReport(uri, resultId: "r3"))
            #expect(await puller.pull(client: server, key: key))

            let requests = workspaceRequests(of: connection)
            #expect(requests == [
                try WorkspaceDiagnosticParams(identifier: "ws", previousResultIds: []).lspAny(),
                try WorkspaceDiagnosticParams(
                    identifier: "ws", previousResultIds: [.init(uri: uri, value: "r1")]
                ).lspAny(),
                try WorkspaceDiagnosticParams(
                    identifier: "ws", previousResultIds: [.init(uri: uri, value: "r2")]
                ).lspAny()
            ])

            try connection.script(.custom, fullReport(uri, resultId: "r4", items: []))
            #expect(await puller.pull(client: server, key: key))
            #expect(workspace.workspace.diagnosticsStore.diagnostics(for: fileURL).isEmpty)
        }
    }

    @Test func serversWithoutWorkspaceDiagnosticsReceiveNoRequest() async throws {
        try await withTempDir { dir in
            let service = fixture.makeService()
            let workspace = try LSPServiceWorkspace(directory: dir, files: ["a.ts": "let a = 1\n"])
            defer { workspace.close() }
            let server = try await service.startServer(for: .typescript, workspacePath: workspace.path)
            let connection = try #require(fixture.created.first).connection

            #expect(server.workspaceDiagnosticsSupport == nil)
            #expect(await WorkspaceDiagnosticsPuller().pull(client: server, key: workspace.key(.typescript)) == false)
            #expect(await WorkspaceDiagnosticsPuller().pullAll(service: service, workspace: workspace.workspace) == ())
            #expect(workspaceRequests(of: connection).isEmpty)
            #expect(connection.requests.contains { $0.method == .custom } == false)
        }
    }

    @Test func dynamicRegistrationEnablesThePullWithItsIdentifier() async throws {
        try await withTempDir { dir in
            let service = fixture.makeService()
            let workspace = try LSPServiceWorkspace(directory: dir, files: ["a.ts": "let a = 1\n"])
            defer { workspace.close() }
            let server = try await service.startServer(for: .typescript, workspacePath: workspace.path)
            let connection = try #require(fixture.created.first).connection
            server.dynamicCapabilities.register([
                Registration(
                    id: "d",
                    method: "textDocument/diagnostic",
                    registerOptions: .hash([
                        "interFileDependencies": .bool(false),
                        "workspaceDiagnostics": .bool(true),
                        "identifier": .string("dyn")
                    ])
                )
            ])
            try connection.script(.custom, WorkspaceDiagnosticReport(items: []))

            await WorkspaceDiagnosticsPuller().pullAll(service: service, workspace: workspace.workspace)

            #expect(server.workspaceDiagnosticsSupport == WorkspaceDiagnosticsSupport(identifier: "dyn"))
            #expect(workspaceRequests(of: connection) == [
                try WorkspaceDiagnosticParams(identifier: "dyn", previousResultIds: []).lspAny()
            ])
        }
    }

    @Test func aRestartedServerStartsWithoutPreviousResultIds() async throws {
        try await withTempDir { dir in
            enableWorkspaceDiagnostics(identifier: nil)
            let service = fixture.makeService()
            let workspace = try LSPServiceWorkspace(directory: dir, files: ["a.ts": "let a = 1\n"])
            defer { workspace.close() }
            let key = workspace.key(.typescript)
            let uri = workspace.uri("a.ts")
            let puller = WorkspaceDiagnosticsPuller()

            let first = try await service.startServer(for: .typescript, workspacePath: workspace.path)
            try fixture.created[0].connection.script(.custom, fullReport(uri, resultId: "r1", items: []))
            await puller.pull(client: first, key: key)

            try await service.restartServer(key)
            let second = try #require(service.languageClients[key])
            #expect(second !== first)
            let secondConnection = fixture.created[1].connection
            try secondConnection.script(.custom, fullReport(uri, resultId: "n1", items: []))
            await puller.pull(client: second, key: key)

            #expect(workspaceRequests(of: secondConnection) == [
                try WorkspaceDiagnosticParams(identifier: nil, previousResultIds: []).lspAny()
            ])
        }
    }

    @Test func aFailingRequestReportsFalseAndAllowsTheNextPull() async throws {
        try await withTempDir { dir in
            enableWorkspaceDiagnostics()
            let service = fixture.makeService()
            let workspace = try LSPServiceWorkspace(directory: dir, files: ["a.ts": "let a = 1\n"])
            defer { workspace.close() }
            let server = try await service.startServer(for: .typescript, workspacePath: workspace.path)
            let connection = try #require(fixture.created.first).connection
            let key = workspace.key(.typescript)
            let puller = WorkspaceDiagnosticsPuller()

            #expect(await puller.pull(client: server, key: key) == false)

            try connection.script(.custom, WorkspaceDiagnosticReport(items: []))
            #expect(await puller.pull(client: server, key: key))
        }
    }

    @Test func overlappingPullsOfTheSameServerSendOneRequest() async throws {
        try await withTempDir { dir in
            enableWorkspaceDiagnostics()
            let service = fixture.makeService()
            let workspace = try LSPServiceWorkspace(directory: dir, files: ["a.ts": "let a = 1\n"])
            defer { workspace.close() }
            let server = try await service.startServer(for: .typescript, workspacePath: workspace.path)
            let connection = try #require(fixture.created.first).connection
            let key = workspace.key(.typescript)
            let puller = WorkspaceDiagnosticsPuller()
            try connection.script(.custom, WorkspaceDiagnosticReport(items: []))

            async let first = puller.pull(client: server, key: key)
            async let second = puller.pull(client: server, key: key)
            let results = await [first, second]

            #expect(results.contains(true))
            #expect(workspaceRequests(of: connection).count == results.filter { $0 }.count)
        }
    }

    @Test func refreshingDiagnosticsPullsEachOpenDocumentAndThenTheWorkspace() async throws {
        try await withTempDir { dir in
            enableWorkspaceDiagnostics()
            let service = fixture.makeService()
            let workspace = try LSPServiceWorkspace(
                directory: dir,
                files: ["a.ts": "let a = 1\n", "b.ts": "let b = 2\n"]
            )
            defer { workspace.close() }
            let document = try workspace.document("a.ts")
            service.openDocument(document)
            await service.waitForDocumentOperations()
            let connection = try #require(fixture.created.first).connection
            let key = workspace.key(.typescript)
            let store = workspace.workspace.diagnosticsStore
            try connection.script(
                .textDocumentDiagnostic,
                DocumentDiagnosticReport(kind: .full, items: [pullTestDiagnostic(message: "document")])
            )
            try connection.script(
                .custom,
                fullReport(workspace.uri("b.ts"), resultId: "w1", items: [pullTestDiagnostic(message: "workspace")])
            )

            let pullsBeforeRefresh = connection.requestCount(.textDocumentDiagnostic)

            await service.refresh(.diagnostics, for: key)

            #expect(connection.requestCount(.textDocumentDiagnostic) - pullsBeforeRefresh == 1)
            #expect(workspaceRequests(of: connection).count == 1)
            #expect(store.diagnostics(for: dir.appending(path: "a.ts")).map(\.message) == ["document"])
            #expect(store.diagnostics(for: dir.appending(path: "b.ts")).map(\.message) == ["workspace"])
        }
    }
}
