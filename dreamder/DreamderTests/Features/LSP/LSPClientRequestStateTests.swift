import Foundation
import JSONRPC
import LanguageServerProtocol
import Synchronization
import Testing
@testable import Dreamder

@Suite
struct LSPDynamicCapabilityRegistryTests {
    @Test
    func registerAndUnregisterById() throws {
        let registry = LSPDynamicCapabilityRegistry()
        registry.register([
            Registration(id: "1", method: "textDocument/hover"),
            Registration(id: "2", method: "textDocument/hover"),
            Registration(id: "3", method: "textDocument/rename")
        ])
        #expect(registry.hasCapability("textDocument/hover"))
        #expect(registry.registrations(for: "textDocument/hover").map(\.id) == ["1", "2"])

        registry.unregister(try lspUnregistrations([("1", "textDocument/hover")]).unregistrations)
        #expect(registry.registrations(for: "textDocument/hover").map(\.id) == ["2"])
        #expect(registry.hasCapability("textDocument/hover"))

        registry.unregister(try lspUnregistrations([("2", "textDocument/hover")]).unregistrations)
        #expect(!registry.hasCapability("textDocument/hover"))
        #expect(registry.registeredMethods == ["textDocument/rename"])
    }

    @Test
    func unregisterRequiresMatchingMethodAndId() throws {
        let registry = LSPDynamicCapabilityRegistry()
        registry.register([Registration(id: "1", method: "textDocument/hover")])
        let unregistrations = try lspUnregistrations([("1", "textDocument/rename"), ("2", "textDocument/hover")])
        registry.unregister(unregistrations.unregistrations)
        #expect(registry.registrations(for: "textDocument/hover").map(\.id) == ["1"])
    }

    @Test
    func registeringTheSameIdTwiceReplacesTheEarlierRegistration() {
        let registry = LSPDynamicCapabilityRegistry()
        registry.register([Registration(id: "1", method: "textDocument/completion", registerOptions: ["a": 1])])
        registry.register([Registration(id: "1", method: "textDocument/completion", registerOptions: ["a": 2])])
        let stored = registry.registrations(for: "textDocument/completion")
        #expect(stored.count == 1)
        #expect(stored.first?.registerOptions == ["a": 2])
    }

    @Test
    func unknownMethodHasNoRegistrations() {
        let registry = LSPDynamicCapabilityRegistry()
        #expect(!registry.hasCapability("textDocument/hover"))
        #expect(registry.registrations(for: "textDocument/hover").isEmpty)
        let options = registry.registerOptions(
            for: "textDocument/hover",
            as: DidChangeWatchedFilesRegistrationOptions.self
        )
        #expect(options.isEmpty)
    }

    @Test
    func registerOptionsSkipRegistrationsThatDoNotDecode() {
        let registry = LSPDynamicCapabilityRegistry()
        registry.register([
            Registration(id: "1", method: "workspace/didChangeWatchedFiles", registerOptions: ["watchers": "invalid"]),
            Registration(id: "2", method: "workspace/didChangeWatchedFiles", registerOptions: nil),
            Registration(
                id: "3",
                method: "workspace/didChangeWatchedFiles",
                registerOptions: ["watchers": [["globPattern": "*.rs"]]]
            )
        ])
        let options = registry.registerOptions(
            for: "workspace/didChangeWatchedFiles",
            as: DidChangeWatchedFilesRegistrationOptions.self
        )
        let expected = DidChangeWatchedFilesRegistrationOptions(watchers: [FileSystemWatcher(globPattern: "*.rs")])
        #expect(options == [expected])
    }

    @Test
    func removeAllClearsEverything() {
        let registry = LSPDynamicCapabilityRegistry()
        registry.register([Registration(id: "1", method: "textDocument/hover")])
        registry.removeAll()
        #expect(registry.registeredMethods.isEmpty)
    }

    @Test
    func refreshKindsMapFromMethods() {
        #expect(LSPRefreshKind(refreshMethod: "workspace/semanticTokens/refresh") == .semanticTokens)
        #expect(LSPRefreshKind(refreshMethod: "workspace/inlayHint/refresh") == .inlayHint)
        #expect(LSPRefreshKind(refreshMethod: "workspace/diagnostic/refresh") == .diagnostics)
        #expect(LSPRefreshKind(refreshMethod: "workspace/codeLens/refresh") == nil)
        #expect(LSPRefreshKind(refreshMethod: "workspace/foldingRange/refresh") == nil)
        #expect(LSPRefreshKind(registrationMethod: "textDocument/inlayHint") == .inlayHint)
        #expect(LSPRefreshKind(registrationMethod: "textDocument/diagnostic") == .diagnostics)
        #expect(LSPRefreshKind(registrationMethod: "textDocument/codeLens") == nil)
        #expect(LSPRefreshKind(registrationMethod: "textDocument/hover") == nil)
    }
}

@Suite
struct LSPWorkDoneProgressTrackerTests {
    private func begin(_ title: String, percentage: Double? = nil) -> LSPAny {
        var value: [String: LSPAny] = ["kind": "begin", "title": .string(title)]
        if let percentage {
            value["percentage"] = .number(percentage)
        }
        return .hash(value)
    }

    @Test
    func beginReportEndLifecycle() {
        let tracker = LSPWorkDoneProgressTracker()
        let token = ProgressToken.optionB("t")
        tracker.create(token)
        #expect(tracker.activeProgresses.isEmpty)

        #expect(tracker.apply(ProgressParams(token: token, value: begin("Indexing", percentage: 10))) == .began)
        #expect(tracker.progress(for: token) == LSPWorkDoneProgress(
            token: token, title: "Indexing", message: nil, percentage: 10, hasBegun: true
        ))

        let report: LSPAny = ["kind": "report", "message": "3/10", "percentage": 30]
        #expect(tracker.apply(ProgressParams(token: token, value: report)) == .reported)
        #expect(tracker.progress(for: token)?.message == "3/10")
        #expect(tracker.progress(for: token)?.percentage == 30)
        #expect(tracker.progress(for: token)?.title == "Indexing")

        #expect(tracker.apply(ProgressParams(token: token, value: ["kind": "end"])) == .ended)
        #expect(tracker.progress(for: token) == nil)
        #expect(tracker.trackedTokenCount == 0)
    }

    @Test
    func reportKeepsPreviousValuesWhenFieldsAreOmitted() {
        let tracker = LSPWorkDoneProgressTracker()
        let token = ProgressToken.optionA(1)
        tracker.apply(ProgressParams(token: token, value: begin("Build", percentage: 40)))
        tracker.apply(ProgressParams(token: token, value: ["kind": "report", "message": "step"]))
        let progress = tracker.progress(for: token)
        #expect(progress?.percentage == 40)
        #expect(progress?.message == "step")
    }

    @Test
    func percentageIsClamped() {
        let tracker = LSPWorkDoneProgressTracker()
        let token = ProgressToken.optionA(1)
        tracker.apply(ProgressParams(token: token, value: begin("Build", percentage: 250)))
        #expect(tracker.progress(for: token)?.percentage == 100)
        tracker.apply(ProgressParams(token: token, value: ["kind": "report", "percentage": -5]))
        #expect(tracker.progress(for: token)?.percentage == 0)
    }

    @Test
    func reportAndEndForUnknownTokensAreIgnored() {
        let tracker = LSPWorkDoneProgressTracker()
        let token = ProgressToken.optionB("unknown")
        #expect(tracker.apply(ProgressParams(token: token, value: ["kind": "report", "message": "x"])) == .ignored)
        #expect(tracker.apply(ProgressParams(token: token, value: ["kind": "end"])) == .ignored)
        #expect(tracker.trackedTokenCount == 0)
    }

    @Test
    func reportForATokenThatOnlyWasCreatedIsIgnored() {
        let tracker = LSPWorkDoneProgressTracker()
        let token = ProgressToken.optionB("created")
        tracker.create(token)
        #expect(tracker.apply(ProgressParams(token: token, value: ["kind": "report", "message": "x"])) == .ignored)
        #expect(tracker.progress(for: token)?.message == nil)
    }

    @Test
    func malformedPayloadsAreIgnored() {
        let tracker = LSPWorkDoneProgressTracker()
        let token = ProgressToken.optionA(1)
        #expect(tracker.apply(ProgressParams(token: token, value: nil)) == .ignored)
        #expect(tracker.apply(ProgressParams(token: token, value: "begin")) == .ignored)
        #expect(tracker.apply(ProgressParams(token: token, value: ["kind": "begin"])) == .ignored)
        #expect(tracker.apply(ProgressParams(token: token, value: ["kind": "other", "title": "x"])) == .ignored)
        #expect(tracker.trackedTokenCount == 0)
    }

    @Test
    func integerAndStringTokensAreDistinct() {
        let tracker = LSPWorkDoneProgressTracker()
        tracker.apply(ProgressParams(token: .optionA(1), value: begin("number")))
        tracker.apply(ProgressParams(token: .optionB("1"), value: begin("string")))
        #expect(tracker.activeProgresses.count == 2)
        #expect(tracker.progress(for: .optionA(1))?.title == "number")
        #expect(tracker.progress(for: .optionB("1"))?.title == "string")
    }

    @Test
    func shutDownDropsEverythingAndRejectsLaterBegins() {
        let tracker = LSPWorkDoneProgressTracker()
        tracker.create(.optionA(1))
        tracker.apply(ProgressParams(token: .optionA(2), value: begin("running")))
        tracker.shutDown()
        #expect(tracker.isShutDown)
        #expect(tracker.trackedTokenCount == 0)
        #expect(tracker.apply(ProgressParams(token: .optionA(3), value: begin("late"))) == .ignored)
        #expect(!tracker.create(.optionA(4)))
        #expect(tracker.trackedTokenCount == 0)
    }
}

@Suite
struct LSPWorkspaceConfigurationTests {
    private let configuration = LSPWorkspaceConfiguration(settings: [
        "python": ["analysis": ["mode": "strict", "paths": ["src"]], "flag": true],
        "typescript.format.semicolons": "insert",
        "typescript": ["format": ["indent": 2]],
        "scalar": 1
    ])

    private func value(_ section: String?) -> LSPAny? {
        configuration.value(for: ConfigurationItem(scopeUri: nil, section: section))
    }

    @Test
    func exactAndNestedSectionsResolve() {
        #expect(value("scalar") == 1)
        #expect(value("python.flag") == true)
        #expect(value("python.analysis.mode") == "strict")
        #expect(value("python.analysis") == ["mode": "strict", "paths": ["src"]])
    }

    @Test
    func flatDottedKeysTakePartInResolution() {
        #expect(value("typescript.format.semicolons") == "insert")
        #expect(value("typescript.format.indent") == 2)
    }

    @Test
    func unknownSectionsAreNil() {
        #expect(value("rust") == nil)
        #expect(value("python.analysis.unknown") == nil)
        #expect(value("scalar.nested") == nil)
        #expect(value("python..flag") == nil)
    }

    @Test
    func missingSectionReturnsAllSettingsOrNil() {
        #expect(value(nil) == .hash(configuration.settings))
        #expect(value("") == .hash(configuration.settings))
        #expect(LSPWorkspaceConfiguration().value(for: ConfigurationItem(scopeUri: nil, section: nil)) == nil)
    }

    @Test
    func workspaceFolderUsesTheRootUriFormat() {
        #expect(LSPWorkspaceFolders.folder(forWorkspacePath: "/Users/me/project")
            == WorkspaceFolder(uri: "file:///Users/me/project", name: "project"))
    }
}
