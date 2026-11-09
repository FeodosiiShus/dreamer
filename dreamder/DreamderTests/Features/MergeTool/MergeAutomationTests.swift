import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
final class InvocationCounter {
    var value = 0
}

@MainActor
final class MenuProbe: NSObject {
    var invocations = 0

    @objc
    func resolve(_ sender: Any?) {
        invocations += 1
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct MergeAutomationTests {
    static let configPath = "app/config.txt"
    static let notesPath = "docs/notes.txt"
    static let mergeSummary = "Merging branch feature into branch main"
    static let mainSide =
        "alpha\nbeta-main\ngamma\ndelta\nepsilon\nzeta-main\neta\ntheta\niota\nkappa\nlambda"
    static let featureSide =
        "alpha\nbeta\ngamma\ndelta\nepsilon\nzeta-feature\neta\ntheta\niota\nkappa\nfeature-added\nlambda"
    static let resolvedLeft =
        "alpha\nbeta-main\ngamma\ndelta\nepsilon\nzeta-main\neta\ntheta\niota\nkappa\nfeature-added\nlambda"
    static let unresolvedResult =
        "alpha\nbeta-main\ngamma\ndelta\nepsilon\nzeta\neta\ntheta\niota\nkappa\nfeature-added\nlambda\n"

    @MainActor
    final class Session {
        let root: URL
        let fixture: GitMergeFixture
        let workspace: WorkspaceDocument

        init(root: URL, fixture: GitMergeFixture) {
            self.root = root
            self.fixture = fixture
            let document = WorkspaceDocument()
            document.sourceControlManager = SourceControlManager(workspaceURL: root, editorManager: EditorManager())
            NSDocumentController.shared.addDocument(document)
            workspace = document
        }

        var path: String {
            root.path(percentEncoded: false)
        }

        func tearDown() async {
            MergeAutomation.registerBanner(path: nil, action: nil)
            MergeToolConfirmation.automationAnswer = nil
            await MergeAutomation.perform("target:")
            for _ in 0..<8 {
                guard let window = MergeToolPresenter.revisionsWindow else { break }
                window.close()
            }
            for _ in 0..<8 {
                guard let window = MergeToolPresenter.conflictsWindow else { break }
                window.close()
            }
            NSDocumentController.shared.removeDocument(workspace)
        }
    }

    func withSession(_ body: (Session) async throws -> Void) async throws {
        try await withTempDir { directory in
            let fixture = try await GitMergeFixture.mergeConflict(in: directory)
            let session = Session(root: directory, fixture: fixture)
            do {
                try await body(session)
            } catch {
                await session.tearDown()
                throw error
            }
            await session.tearDown()
        }
    }

    func openConflicts(_ session: Session) async throws -> MergeConflictsViewModel {
        await MergeAutomation.perform("target:\(session.path)")
        await MergeAutomation.perform("conflicts:")
        let model = try #require(MergeToolPresenter.conflictsModel(for: session.workspace))
        try await eventually { model.entries.count == 2 && model.summary == Self.mergeSummary }
        return model
    }

    func openRevisions(
        _ session: Session,
        path: String = MergeAutomationTests.configPath
    ) async throws -> MergeRevisionsViewModel {
        await MergeAutomation.perform("target:\(session.path)")
        await MergeAutomation.perform("mergeFile:\(path)")
        let model = try #require(MergeToolPresenter.revisionsModel)
        try await eventually { model.isLoading == false }
        return model
    }

    func conflictBlockID(_ model: MergeRevisionsViewModel) throws -> Int {
        let merge = try #require(model.merge)
        return try #require(merge.blocks.first { $0.kind == .conflict }).id
    }

    func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func dumpLines(_ session: Session) async throws -> [String] {
        let directory = session.root.appending(path: "dump-output")
        await MergeAutomation.perform("dump:\(directory.path(percentEncoded: false))")
        let text = try String(contentsOf: directory.appending(path: "merge.txt"), encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    func value(_ key: String, in lines: [String]) -> String? {
        lines.first { $0.hasPrefix(key + "=") }.map { String($0.dropFirst(key.count + 1)) }
    }

    func values(_ key: String, in lines: [String]) -> [String] {
        lines.filter { $0.hasPrefix(key + "=") }.map { String($0.dropFirst(key.count + 1)) }
    }

    func paneTextView(_ pane: String) -> NSTextView? {
        guard let content = MergeToolPresenter.revisionsWindow?.contentView else { return nil }
        content.layoutSubtreeIfNeeded()
        return findTextView(in: content, identifier: "merge-pane-\(pane)")
    }

    func findTextView(in view: NSView, identifier: String) -> NSTextView? {
        if let textView = view as? NSTextView, textView.identifier?.rawValue == identifier {
            return textView
        }
        for subview in view.subviews {
            if let found = findTextView(in: subview, identifier: identifier) {
                return found
            }
        }
        return nil
    }

    @Test
    func targetCommandRemembersTheProjectPath() async {
        await MergeAutomation.perform("target:/tmp/dreamder-first")
        #expect(MergeAutomation.targetPath == "/tmp/dreamder-first")
        await MergeAutomation.perform("target:/tmp/dreamder-second")
        #expect(MergeAutomation.targetPath == "/tmp/dreamder-second")
        await MergeAutomation.perform("target:")
        #expect(MergeAutomation.targetPath == "")
    }

    @Test
    func emptyAndUnknownCommandsChangeNothing() async {
        await MergeAutomation.perform("target:/tmp/dreamder-stable")
        await MergeAutomation.perform("")
        await MergeAutomation.perform(":payload")
        await MergeAutomation.perform("noSuchCommand:1:2")
        await MergeAutomation.perform("target:/tmp/dreamder-stable")
        #expect(MergeAutomation.targetPath == "/tmp/dreamder-stable")
        #expect(MergeToolPresenter.conflictsWindow == nil)
        #expect(MergeToolPresenter.revisionsWindow == nil)
        await MergeAutomation.perform("target:")
    }

    @Test
    func commandsWithoutOpenWindowsAreHarmless() async {
        for command in [
            "select:app/config.txt", "selectAdd:app/config.txt", "selectRange:app/config.txt",
            "acceptYours", "acceptTheirs", "mergeSelected", "resolve:1:left", "clickChip:left:1:left",
            "applyNonConflicting:all", "editResult:text", "acceptLeft", "acceptRight", "apply", "cancel",
            "closeRevisions", "closeConflicts", "mergeFile:", "bannerResolve"
        ] {
            await MergeAutomation.perform(command)
        }
        #expect(MergeToolPresenter.conflictsModel == nil)
        #expect(MergeToolPresenter.revisionsModel == nil)
    }

    @Test
    func queueRunsCommandsStrictlyInSubmissionOrder() async throws {
        try await withSession { session in
            MergeAutomation.enqueue("target:\(session.path)")
            MergeAutomation.enqueue("conflicts:")
            MergeAutomation.enqueue("select:\(Self.notesPath)")
            await MergeAutomation.queue.value

            let model = try #require(MergeToolPresenter.conflictsModel(for: session.workspace))
            #expect(MergeAutomation.targetPath == session.path)
            #expect(model.selectedPaths == [Self.notesPath])
            #expect(model.primaryPath == Self.notesPath)
        }
    }

    @Test
    func conflictsCommandOpensTheDialogForTheTargetWorkspace() async throws {
        try await withSession { session in
            let model = try await openConflicts(session)

            #expect(model.entries.map(\.path) == [Self.configPath, Self.notesPath])
            #expect(model.workspace === session.workspace)
            #expect(MergeToolPresenter.conflictsWindow?.title == "Conflicts")
            #expect(MergeToolPresenter.conflictsModel === model)
        }
    }

    @Test
    func conflictsCommandWithPathPicksTheMatchingWorkspace() async throws {
        try await withSession { session in
            try await withTempDir { otherDirectory in
                let otherFixture = try await GitMergeFixture(root: otherDirectory)
                try otherFixture.write("a.txt", "a\n")
                try await otherFixture.commit("initial")
                let other = Session(root: otherDirectory, fixture: otherFixture)
                defer { NSDocumentController.shared.removeDocument(other.workspace) }

                await MergeAutomation.perform("conflicts:\(session.path)")

                let model = try #require(MergeToolPresenter.conflictsModel(for: session.workspace))
                try await eventually { model.entries.count == 2 }
                #expect(MergeToolPresenter.conflictsModel(for: other.workspace) == nil)
            }
        }
    }

    @Test
    func selectionCommandsFollowTableSemantics() async throws {
        try await withSession { session in
            let model = try await openConflicts(session)

            await MergeAutomation.perform("select:\(Self.configPath)")
            #expect(model.selectedPaths == [Self.configPath])
            #expect(model.primaryPath == Self.configPath)

            await MergeAutomation.perform("selectRange:\(Self.notesPath)")
            #expect(model.selectedPaths == [Self.configPath, Self.notesPath])
            #expect(model.primaryPath == Self.notesPath)

            await MergeAutomation.perform("select:\(Self.notesPath)")
            #expect(model.selectedPaths == [Self.notesPath])

            await MergeAutomation.perform("selectAdd:\(Self.configPath)")
            #expect(model.selectedPaths == [Self.configPath, Self.notesPath])
            #expect(model.primaryPath == Self.configPath)

            await MergeAutomation.perform("selectAdd:\(Self.configPath)")
            #expect(model.selectedPaths == [Self.notesPath])
            #expect(model.primaryPath == Self.notesPath)
        }
    }
}
