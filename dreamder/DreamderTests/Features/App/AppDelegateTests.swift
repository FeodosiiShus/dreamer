import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageClient
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct AppDelegateTests {
    struct OpenFailure: LocalizedError {
        var errorDescription: String? { "Cannot open AppDelegateTests fixture" }
    }

    @MainActor
    final class StubDocumentController: AppDocumentControlling {
        var stubbedDocuments: [NSDocument] = []
        var documentToReturn: NSDocument?
        var errorToReturn: (any Error)?
        var closeAllCompletes = true
        var closesDocumentsOnCloseAll = false
        private(set) var openedURLs: [URL] = []
        private(set) var openPanelCalls = 0
        private(set) var newDocumentCalls = 0
        private(set) var closeAllCalls = 0

        var documents: [NSDocument] { stubbedDocuments }

        func openDocument(
            withContentsOf url: URL,
            display displayDocument: Bool,
            completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void
        ) {
            openedURLs.append(url)
            completionHandler(documentToReturn, false, errorToReturn)
        }

        func openDocument(_ sender: Any?) {
            openPanelCalls += 1
        }

        func newDocument(_ sender: Any?) {
            newDocumentCalls += 1
        }

        func closeAllDocuments(
            withDelegate delegate: Any?,
            didCloseAllSelector: Selector?,
            contextInfo: UnsafeMutableRawPointer?
        ) {
            closeAllCalls += 1
            if closesDocumentsOnCloseAll {
                let closing = stubbedDocuments
                stubbedDocuments = []
                closing.forEach { $0.close() }
            }
            (delegate as? AppDelegate)?.documentController(
                NSDocumentController.shared,
                didCloseAll: closeAllCompletes,
                contextInfo: contextInfo
            )
        }
    }

    @MainActor
    final class EditedDocument: NSDocument {
        override var isDocumentEdited: Bool { true }
    }

    @MainActor
    final class RecordingTaskManager: TaskManager {
        private(set) var stopAllCalls = 0

        override func stopAllTasks() {
            stopAllCalls += 1
        }
    }

    @MainActor
    final class TerminationRecorder {
        private(set) var replies: [Bool] = []
        private(set) var notifications: [String] = []
        private var observer: NSObjectProtocol?

        init() {
            observer = NotificationCenter.default.addObserver(
                forName: .taskNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let identifier = notification.userInfo?["id"] as? String ?? ""
                let action = notification.userInfo?["action"] as? String ?? ""
                guard identifier.hasPrefix("appdelegate.") else { return }
                MainActor.assumeIsolated {
                    self?.notifications.append("\(identifier):\(action)")
                }
            }
        }

        isolated deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func record(reply: Bool) {
            replies.append(reply)
        }
    }

    @MainActor
    struct TerminationHarness {
        let delegate: AppDelegate
        let service: LSPService
        let controller: StubDocumentController
        let recorder: TerminationRecorder
        let defaults: UserDefaults
        let suiteName: String

        init() throws {
            let isolated = try makeIsolatedDefaults()
            let recorder = TerminationRecorder()
            let service = LSPService()
            let delegate = AppDelegate()
            let controller = StubDocumentController()
            delegate.documentsController = controller
            delegate.defaults = isolated.defaults
            delegate.languageService = { service }
            delegate.replyToTerminate = { recorder.record(reply: $0) }
            self.delegate = delegate
            self.service = service
            self.controller = controller
            self.recorder = recorder
            self.defaults = isolated.defaults
            self.suiteName = isolated.suiteName
        }

        func tearDown() {
            removeIsolatedDefaults(defaults, suiteName: suiteName)
        }
    }

    func makeWorkspace(at directory: URL) throws -> WorkspaceDocument {
        try WorkspaceDocument(for: directory, withContentsOf: directory, ofType: "")
    }

    func makeCodeFile(in directory: URL, name: String = "Opened.txt") throws -> CodeFileDocument {
        let url = directory.appending(path: name)
        try "alpha\nbravo\n".write(to: url, atomically: true, encoding: .utf8)
        return try CodeFileDocument(for: url, withContentsOf: url, ofType: "public.plain-text")
    }

    func withReopenBehavior(
        _ behavior: SettingsData.ReopenBehavior,
        _ body: (AppDelegate) throws -> Void
    ) throws {
        try withTempDir { directory in
            let settings = Dreamder.Settings(baseURL: directory)
            settings.preferences.general.reopenBehavior = behavior
            let delegate = AppDelegate()
            delegate.settings = settings
            try body(delegate)
        }
    }

    @Test(arguments: [
        ([String](), [String]()),
        (["Dreamder"], []),
        (["Dreamder", "--open"], []),
        (["Dreamder", "--open", "/tmp/a.swift"], ["/tmp/a.swift"]),
        (["--open", "/tmp/a", "-x", "--open", "/tmp/b"], ["/tmp/a", "/tmp/b"]),
        (["/tmp/not-a-flag", "--other", "/tmp/c"], [])
    ])
    func openArgumentsYieldTheValueFollowingEachOpenFlag(arguments: [String], expected: [String]) {
        #expect(AppDelegate.openURLs(fromArguments: arguments).map(\.path) == expected)
    }

    @Test
    func finderExtensionRequestOpensEveryListedFileAndClearsTheRequest() throws {
        let isolated = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
        isolated.defaults.set(
            ["/tmp/Alpha.swift", "/tmp/with space/Beta.txt", "", "/tmp/semi;colon:name.md"],
            forKey: "openInCEFiles"
        )
        let delegate = AppDelegate()
        var opened: [String] = []
        delegate.reopenDocument = { opened.append($0.path) }

        delegate.openFilesRequestedByFinderExtension(defaults: isolated.defaults)

        #expect(opened == ["/tmp/Alpha.swift", "/tmp/with space/Beta.txt", "/tmp/semi;colon:name.md"])
        #expect(isolated.defaults.object(forKey: "openInCEFiles") == nil)
    }

    @Test
    func finderExtensionWithoutARequestOpensNothingAndEnablesOpenInDreamder() throws {
        let isolated = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
        let delegate = AppDelegate()
        var opened: [URL] = []
        delegate.reopenDocument = { opened.append($0) }

        delegate.openFilesRequestedByFinderExtension(defaults: isolated.defaults)

        #expect(opened.isEmpty)
        #expect(isolated.defaults.object(forKey: "enableOpenInCE") as? Bool == true)
    }

    @Test
    func finderExtensionRequestWithOnlyAnEmptyPathOpensNothingButIsStillCleared() throws {
        let isolated = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
        isolated.defaults.set([""], forKey: "openInCEFiles")
        let delegate = AppDelegate()
        var opened: [URL] = []
        delegate.reopenDocument = { opened.append($0) }

        delegate.openFilesRequestedByFinderExtension(defaults: isolated.defaults)

        #expect(opened.isEmpty)
        #expect(isolated.defaults.object(forKey: "openInCEFiles") == nil)
    }

    @Test
    func finderExtensionRequestInTheObsoleteStringFormatOpensNothingButIsStillCleared() throws {
        let isolated = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
        isolated.defaults.set("/tmp/Alpha.swift;/tmp/Beta.swift", forKey: "openInCEFiles")
        let delegate = AppDelegate()
        var opened: [URL] = []
        delegate.reopenDocument = { opened.append($0) }

        delegate.openFilesRequestedByFinderExtension(defaults: isolated.defaults)

        #expect(opened.isEmpty)
        #expect(isolated.defaults.object(forKey: "openInCEFiles") == nil)
    }
}
