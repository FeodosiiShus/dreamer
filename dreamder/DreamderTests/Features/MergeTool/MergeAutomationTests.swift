import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
private final class InvocationCounter {
    var value = 0
}

@MainActor
private final class MenuProbe: NSObject {
    var invocations = 0

    @objc func resolve(_ sender: Any?) {
        invocations += 1
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct MergeAutomationTests {
    private static let configPath = "app/config.txt"
    private static let notesPath = "docs/notes.txt"
    private static let mergeSummary = "Merging branch feature into branch main"
    private static let mainSide =
        "alpha\nbeta-main\ngamma\ndelta\nepsilon\nzeta-main\neta\ntheta\niota\nkappa\nlambda"
    private static let featureSide =
        "alpha\nbeta\ngamma\ndelta\nepsilon\nzeta-feature\neta\ntheta\niota\nkappa\nfeature-added\nlambda"
    private static let resolvedLeft =
        "alpha\nbeta-main\ngamma\ndelta\nepsilon\nzeta-main\neta\ntheta\niota\nkappa\nfeature-added\nlambda"
    private static let unresolvedResult =
        "alpha\nbeta-main\ngamma\ndelta\nepsilon\nzeta\neta\ntheta\niota\nkappa\nfeature-added\nlambda\n"

    @MainActor
    private final class Session {
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

    private func withSession(_ body: (Session) async throws -> Void) async throws {
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

    private func openConflicts(_ session: Session) async throws -> MergeConflictsViewModel {
        await MergeAutomation.perform("target:\(session.path)")
        await MergeAutomation.perform("conflicts:")
        let model = try #require(MergeToolPresenter.conflictsModel(for: session.workspace))
        try await eventually { model.entries.count == 2 && model.summary == Self.mergeSummary }
        return model
    }

    private func openRevisions(
        _ session: Session,
        path: String = MergeAutomationTests.configPath
    ) async throws -> MergeRevisionsViewModel {
        await MergeAutomation.perform("target:\(session.path)")
        await MergeAutomation.perform("mergeFile:\(path)")
        let model = try #require(MergeToolPresenter.revisionsModel)
        try await eventually { model.isLoading == false }
        return model
    }

    private func conflictBlockID(_ model: MergeRevisionsViewModel) throws -> Int {
        let merge = try #require(model.merge)
        return try #require(merge.blocks.first { $0.kind == .conflict }).id
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func dumpLines(_ session: Session) async throws -> [String] {
        let directory = session.root.appending(path: "dump-output")
        await MergeAutomation.perform("dump:\(directory.path(percentEncoded: false))")
        let text = try String(contentsOf: directory.appending(path: "merge.txt"), encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    private func value(_ key: String, in lines: [String]) -> String? {
        lines.first { $0.hasPrefix(key + "=") }.map { String($0.dropFirst(key.count + 1)) }
    }

    private func values(_ key: String, in lines: [String]) -> [String] {
        lines.filter { $0.hasPrefix(key + "=") }.map { String($0.dropFirst(key.count + 1)) }
    }

    private func paneTextView(_ pane: String) -> NSTextView? {
        guard let content = MergeToolPresenter.revisionsWindow?.contentView else { return nil }
        content.layoutSubtreeIfNeeded()
        return findTextView(in: content, identifier: "merge-pane-\(pane)")
    }

    private func findTextView(in view: NSView, identifier: String) -> NSTextView? {
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

    @Test
    func acceptYoursKeepsOursForTheSelectedFile() async throws {
        try await withSession { session in
            let model = try await openConflicts(session)
            await MergeAutomation.perform("select:\(Self.configPath)")

            await MergeAutomation.perform("acceptYours")

            #expect(try trimmed(session.fixture.read(Self.configPath)) == Self.mainSide)
            #expect(try await session.fixture.isFullyStaged(Self.configPath))
            #expect(try await session.fixture.unmergedPaths() == [Self.notesPath])
            try await eventually { model.entries.map(\.path) == [Self.notesPath] }
            #expect(model.primaryPath == Self.notesPath)
            #expect(model.errorMessage == nil)
        }
    }

    @Test
    func acceptTheirsTakesTheOtherSideForEverySelectedFile() async throws {
        try await withSession { session in
            let model = try await openConflicts(session)
            await MergeAutomation.perform("select:\(Self.configPath)")
            await MergeAutomation.perform("selectAdd:\(Self.notesPath)")

            await MergeAutomation.perform("acceptTheirs")

            #expect(try trimmed(session.fixture.read(Self.configPath)) == Self.featureSide)
            #expect(try trimmed(session.fixture.read(Self.notesPath)) == "one\nnotes-feature\nthree")
            #expect(try await session.fixture.unmergedPaths().isEmpty)
            try await eventually { model.entries.isEmpty }
            #expect(model.summary == "All conflicts have been resolved")
        }
    }

    @Test
    func mergeSelectedOpensTheRevisionsWindowForThePrimaryFile() async throws {
        try await withSession { session in
            _ = try await openConflicts(session)
            await MergeAutomation.perform("select:\(Self.notesPath)")

            await MergeAutomation.perform("mergeSelected")

            #expect(MergeToolPresenter.lastRevisionsPath == Self.notesPath)
            let model = try #require(MergeToolPresenter.revisionsModel)
            #expect(model.path == Self.notesPath)
            try await eventually { model.isLoading == false }
            #expect(model.merge?.conflictCount == 1)
        }
    }

    @Test
    func mergeFileOpensTheRevisionsWindowForTheGivenPath() async throws {
        try await withSession { session in
            let model = try await openRevisions(session)

            #expect(model.path == Self.configPath)
            #expect(model.isConflictValid)
            #expect(model.leftTitle == "Your version, branch main")
            #expect(model.rightTitle == "Theirs, branch feature")
            #expect(model.merge?.conflictCount == 1)
            #expect(model.resultText == Self.unresolvedResult)
        }
    }

    @Test
    func mergeFileWithoutPathOpensNothing() async throws {
        try await withSession { session in
            await MergeAutomation.perform("target:\(session.path)")
            await MergeAutomation.perform("mergeFile:")

            #expect(MergeToolPresenter.revisionsModel == nil)
            #expect(MergeToolPresenter.revisionsWindow == nil)
        }
    }

    @Test
    func mergeFileForAnAlreadyResolvedPathReportsAnInvalidConflict() async throws {
        try await withSession { session in
            let model = try await openRevisions(session, path: "not-in-conflict.txt")

            #expect(model.isConflictValid == false)
            #expect(model.errorMessage == "Conflict is not valid and no longer can be resolved.")
            #expect(model.merge == nil)
        }
    }

    @Test(arguments: [
        ("left", "epsilon\nzeta-main\neta"),
        ("right", "epsilon\nzeta-feature\neta"),
        ("ignored", "epsilon\nzeta\neta")
    ])
    func resolveCommandAppliesTheChosenSideToTheBlock(resolution: String, expectedFragment: String) async throws {
        try await withSession { session in
            let model = try await openRevisions(session)
            let blockID = try conflictBlockID(model)

            await MergeAutomation.perform("resolve:\(blockID):\(resolution)")

            #expect(model.resultText.contains(expectedFragment))
            #expect(model.merge?.conflictCount == 0)
            #expect(model.isResultEdited == false)
        }
    }

    @Test(arguments: ["resolve:{id}:sideways", "resolve:{id}", "resolve:abc:left", "resolve::left"])
    func resolveCommandIgnoresMalformedArguments(template: String) async throws {
        try await withSession { session in
            let model = try await openRevisions(session)
            let blockID = try conflictBlockID(model)

            await MergeAutomation.perform(template.replacingOccurrences(of: "{id}", with: String(blockID)))

            #expect(model.merge?.conflictCount == 1)
            #expect(model.resultText == Self.unresolvedResult)
        }
    }

    @Test(arguments: [
        ("left", "alpha\nbeta-main\ngamma\ndelta\nepsilon\nzeta\neta\ntheta\niota\nkappa\nlambda\n"),
        ("right", "alpha\nbeta\ngamma\ndelta\nepsilon\nzeta\neta\ntheta\niota\nkappa\nfeature-added\nlambda\n"),
        ("all", "alpha\nbeta-main\ngamma\ndelta\nepsilon\nzeta\neta\ntheta\niota\nkappa\nfeature-added\nlambda\n")
    ])
    func applyNonConflictingCommandAppliesOnlyTheRequestedSide(mode: String, expected: String) async throws {
        try await withSession { session in
            let model = try await openRevisions(session)

            await MergeAutomation.perform("applyNonConflicting:\(mode)")

            #expect(TextDiff.lines(in: model.resultText) == TextDiff.lines(in: expected))
        }
    }

    @Test
    func applyNonConflictingCommandIgnoresUnknownModes() async throws {
        try await withSession { session in
            let model = try await openRevisions(session)
            let before = model.resultText
            let revision = model.contentRevision

            await MergeAutomation.perform("applyNonConflicting:sideways")
            await MergeAutomation.perform("applyNonConflicting:")

            #expect(model.resultText == before)
            #expect(model.contentRevision == revision)
        }
    }

    @Test(arguments: [
        ("editResult:hand\\nwritten", "hand\nwritten"),
        ("editResult:let value: Int = 1", "let value: Int = 1"),
        ("editResult:a:b:c", "a:b:c"),
        ("editResult:a\\\\nb", "a\\nb"),
        ("editResult:tab\\r\\nend", "tab\r\nend"),
        ("editResult:dangling\\", "dangling\\"),
        ("editResult:odd\\tescape", "odd\\tescape"),
        ("editResult:", "")
    ])
    func editResultCommandUnescapesTheTypedText(command: String, expected: String) async throws {
        try await withSession { session in
            let model = try await openRevisions(session)

            await MergeAutomation.perform(command)

            #expect(model.resultText == expected)
            #expect(model.isResultEdited)
        }
    }

    @Test
    func acceptLeftWritesTheLeftSideAndClosesTheWindow() async throws {
        try await withSession { session in
            _ = try await openRevisions(session)

            await MergeAutomation.perform("acceptLeft")

            #expect(try trimmed(session.fixture.read(Self.configPath)) == Self.mainSide)
            #expect(try await session.fixture.isFullyStaged(Self.configPath))
            try await eventually { MergeToolPresenter.revisionsWindow == nil }
        }
    }

    @Test
    func acceptRightWritesTheRightSideAndClosesTheWindow() async throws {
        try await withSession { session in
            _ = try await openRevisions(session)

            await MergeAutomation.perform("acceptRight")

            #expect(try trimmed(session.fixture.read(Self.configPath)) == Self.featureSide)
            #expect(try await session.fixture.unmergedPaths() == [Self.notesPath])
            try await eventually { MergeToolPresenter.revisionsWindow == nil }
        }
    }

    @Test
    func acceptLeftAfterEditsNeedsConfirmation() async throws {
        try await withSession { session in
            let model = try await openRevisions(session)
            await MergeAutomation.perform("editResult:draft")

            await MergeAutomation.perform("confirm:no")
            await MergeAutomation.perform("acceptLeft")

            #expect(MergeToolConfirmation.automationAnswer == nil)
            #expect(session.fixture.hasConflictMarkers(Self.configPath))
            #expect(MergeToolPresenter.revisionsWindow != nil)
            #expect(model.isResultEdited)

            await MergeAutomation.perform("confirm:yes")
            await MergeAutomation.perform("acceptLeft")

            #expect(try trimmed(session.fixture.read(Self.configPath)) == Self.mainSide)
            try await eventually { MergeToolPresenter.revisionsWindow == nil }
        }
    }

    @Test
    func applyWritesTheResolvedResultAndClosesTheWindow() async throws {
        try await withSession { session in
            let model = try await openRevisions(session)
            let blockID = try conflictBlockID(model)
            await MergeAutomation.perform("resolve:\(blockID):left")

            await MergeAutomation.perform("apply")

            #expect(try trimmed(session.fixture.read(Self.configPath)) == Self.resolvedLeft)
            #expect(session.fixture.hasConflictMarkers(Self.configPath) == false)
            #expect(try await session.fixture.isFullyStaged(Self.configPath))
            try await eventually { MergeToolPresenter.revisionsWindow == nil }
        }
    }

    @Test
    func applyWithUnresolvedConflictsAsksBeforeSaving() async throws {
        try await withSession { session in
            _ = try await openRevisions(session)

            await MergeAutomation.perform("confirm:no")
            await MergeAutomation.perform("apply")

            #expect(MergeToolConfirmation.automationAnswer == nil)
            #expect(session.fixture.hasConflictMarkers(Self.configPath))
            #expect(MergeToolPresenter.revisionsWindow != nil)

            await MergeAutomation.perform("confirm:yes")
            await MergeAutomation.perform("apply")

            #expect(try trimmed(session.fixture.read(Self.configPath)) == trimmed(Self.unresolvedResult))
            #expect(try await session.fixture.unmergedPaths() == [Self.notesPath])
            try await eventually { MergeToolPresenter.revisionsWindow == nil }
        }
    }

    @Test
    func applyWritesTheTextTypedByEditResult() async throws {
        try await withSession { session in
            _ = try await openRevisions(session)
            await MergeAutomation.perform("editResult:hand\\nwritten: text")
            await MergeAutomation.perform("confirm:yes")

            await MergeAutomation.perform("apply")

            #expect(try session.fixture.read(Self.configPath) == "hand\nwritten: text")
            try await eventually { MergeToolPresenter.revisionsWindow == nil }
        }
    }

    @Test
    func cancelClosesAnUneditedWindowWithoutTouchingTheFile() async throws {
        try await withSession { session in
            _ = try await openRevisions(session)

            await MergeAutomation.perform("cancel")

            #expect(session.fixture.hasConflictMarkers(Self.configPath))
            try await eventually { MergeToolPresenter.revisionsWindow == nil }
        }
    }

    @Test
    func cancelAfterEditsKeepsTheWindowUnlessDiscardIsConfirmed() async throws {
        try await withSession { session in
            let model = try await openRevisions(session)
            await MergeAutomation.perform("editResult:draft")

            await MergeAutomation.perform("confirm:no")
            await MergeAutomation.perform("cancel")

            #expect(MergeToolPresenter.revisionsWindow != nil)
            #expect(model.isResultEdited)

            await MergeAutomation.perform("confirm:yes")
            await MergeAutomation.perform("cancel")

            #expect(session.fixture.hasConflictMarkers(Self.configPath))
            try await eventually { MergeToolPresenter.revisionsWindow == nil }
        }
    }

    @Test
    func closeRevisionsClosesACleanWindow() async throws {
        try await withSession { session in
            _ = try await openRevisions(session)

            await MergeAutomation.perform("closeRevisions")

            try await eventually { MergeToolPresenter.revisionsWindow == nil }
            #expect(MergeToolPresenter.revisionsModel == nil)
        }
    }

    @Test
    func closeRevisionsAfterEditsAsksForConfirmationFirst() async throws {
        try await withSession { session in
            let model = try await openRevisions(session)
            await MergeAutomation.perform("editResult:draft")

            await MergeAutomation.perform("confirm:no")
            await MergeAutomation.perform("closeRevisions")
            try await eventually { MergeToolConfirmation.automationAnswer == nil }

            #expect(MergeToolPresenter.revisionsWindow != nil)
            #expect(model.isResultEdited)

            await MergeAutomation.perform("confirm:yes")
            await MergeAutomation.perform("closeRevisions")
            try await eventually { MergeToolPresenter.revisionsWindow == nil }
        }
    }

    @Test
    func closeConflictsClosesTheConflictsDialog() async throws {
        try await withSession { session in
            _ = try await openConflicts(session)
            #expect(MergeToolPresenter.conflictsWindow != nil)

            await MergeAutomation.perform("closeConflicts")

            try await eventually { MergeToolPresenter.conflictsWindow == nil }
            #expect(MergeToolPresenter.conflictsModel == nil)
        }
    }

    @Test
    func clickChipTriggersTheChipActionInThePane() async throws {
        try await withSession { session in
            let model = try await openRevisions(session)
            let blockID = try conflictBlockID(model)
            try await eventually(timeout: .seconds(30)) {
                paneTextView("left")?.string.contains("zeta-main") == true
                    && paneTextView("right")?.string.contains("zeta-feature") == true
            }

            for command in [
                "clickChip:left:\(blockID):right",
                "clickChip:right:\(blockID):left",
                "clickChip:result:\(blockID):left",
                "clickChip:middle:\(blockID):left",
                "clickChip:left:abc:left",
                "clickChip:left:\(blockID)",
                "clickChip:left:\(blockID):left:extra",
                "clickChip:left:\(blockID):bogus"
            ] {
                await MergeAutomation.perform(command)
                #expect(model.merge?.conflictCount == 1)
            }

            await MergeAutomation.perform("clickChip:left:\(blockID):left")

            #expect(model.merge?.conflictCount == 0)
            #expect(model.resultText.contains("epsilon\nzeta-main\neta"))
        }
    }

    @Test(arguments: [
        ("right", "right", "epsilon\nzeta-feature\neta"),
        ("left", "ignore", "epsilon\nzeta\neta"),
        ("right", "ignore", "epsilon\nzeta\neta")
    ])
    func clickChipSupportsEveryPaneAndAction(pane: String, action: String, expectedFragment: String) async throws {
        try await withSession { session in
            let model = try await openRevisions(session)
            let blockID = try conflictBlockID(model)
            try await eventually(timeout: .seconds(30)) {
                paneTextView(pane)?.string.contains("zeta") == true
            }

            await MergeAutomation.perform("clickChip:\(pane):\(blockID):\(action)")

            #expect(model.merge?.conflictCount == 0)
            #expect(model.resultText.contains(expectedFragment))
        }
    }

    @Test
    func confirmCommandAnswersTheNextQuestionOnce() async {
        await MergeAutomation.perform("confirm:yes")
        #expect(MergeToolConfirmation.automationAnswer == true)
        let first = await MergeToolConfirmation.ask(
            window: nil,
            title: "t",
            message: "m",
            confirmTitle: "c",
            cancelTitle: "x"
        )
        #expect(first)
        #expect(MergeToolConfirmation.automationAnswer == nil)

        await MergeAutomation.perform("confirm:no")
        #expect(MergeToolConfirmation.automationAnswer == false)
        let second = await MergeToolConfirmation.ask(
            window: nil,
            title: "t",
            message: "m",
            confirmTitle: "c",
            cancelTitle: "x"
        )
        #expect(second == false)
        #expect(MergeToolConfirmation.automationAnswer == nil)

        await MergeAutomation.perform("confirm:maybe")
        #expect(MergeToolConfirmation.automationAnswer == false)
        MergeToolConfirmation.automationAnswer = nil
    }

    @Test
    func bannerResolveInvokesTheRegisteredBannerAction() async {
        let counter = InvocationCounter()
        MergeAutomation.registerBanner(path: "app/config.txt") { counter.value += 1 }

        await MergeAutomation.perform("bannerResolve")
        await MergeAutomation.perform("bannerResolve")
        #expect(counter.value == 2)

        MergeAutomation.registerBanner(path: nil, action: nil)
        await MergeAutomation.perform("bannerResolve")
        #expect(counter.value == 2)
    }

    @Test
    func menuResolveActivatesTheGitMenuItemAndDumpReportsIt() async throws {
        try await withSession { session in
            let probe = MenuProbe()
            let item = NSMenuItem(
                title: "Resolve Conflicts…",
                action: #selector(MenuProbe.resolve(_:)),
                keyEquivalent: ""
            )
            item.target = probe
            let gitMenu = NSMenu(title: "Git")
            gitMenu.addItem(NSMenuItem(title: "Update Project", action: nil, keyEquivalent: ""))
            gitMenu.addItem(item)
            let gitItem = NSMenuItem(title: "Git", action: nil, keyEquivalent: "")
            gitItem.submenu = gitMenu
            let mainMenu = NSMenu()
            mainMenu.addItem(gitItem)

            let savedMenu = NSApp.mainMenu
            defer { NSApp.mainMenu = savedMenu }
            NSApp.mainMenu = mainMenu
            await MergeAutomation.perform("menuResolve")
            let withMenu = try await dumpLines(session)
            NSApp.mainMenu = NSMenu()
            await MergeAutomation.perform("menuResolve")
            let withoutMenu = try await dumpLines(session)

            #expect(probe.invocations == 1)
            #expect(value("menu.resolvePresent", in: withMenu) == "1")
            #expect(value("menu.resolveEnabled", in: withMenu) == "1")
            #expect(value("menu.resolveTitle", in: withMenu) == "Resolve Conflicts…")
            #expect(value("menu.resolvePresent", in: withoutMenu) == "0")
            #expect(value("menu.resolveEnabled", in: withoutMenu) == "0")
            #expect(value("menu.resolveTitle", in: withoutMenu) == "")
        }
    }

    @Test
    func menuResolveReportsADisabledMenuItem() async throws {
        try await withSession { session in
            let probe = MenuProbe()
            let item = NSMenuItem(
                title: "Resolve Conflicts…",
                action: #selector(MenuProbe.resolve(_:)),
                keyEquivalent: ""
            )
            item.target = probe
            item.isEnabled = false
            let gitMenu = NSMenu(title: "Git")
            gitMenu.autoenablesItems = false
            gitMenu.addItem(item)
            let gitItem = NSMenuItem(title: "Git", action: nil, keyEquivalent: "")
            gitItem.submenu = gitMenu
            let mainMenu = NSMenu()
            mainMenu.addItem(gitItem)

            let savedMenu = NSApp.mainMenu
            defer { NSApp.mainMenu = savedMenu }
            NSApp.mainMenu = mainMenu
            let lines = try await dumpLines(session)

            #expect(value("menu.resolvePresent", in: lines) == "1")
            #expect(value("menu.resolveEnabled", in: lines) == "0")
        }
    }

    @Test
    func focusWorkspaceBringsTheMatchingWorkspaceWindowToTheFront() async throws {
        try await withTempDir { firstDirectory in
            try await withTempDir { secondDirectory in
                let first = WorkspaceDocument()
                try first.read(from: firstDirectory, ofType: "")
                NSDocumentController.shared.addDocument(first)
                first.makeWindowControllers()
                let firstWindow = try #require(first.windowControllers.first?.window)
                firstWindow.isReleasedWhenClosed = false
                let second = WorkspaceDocument()
                try second.read(from: secondDirectory, ofType: "")
                NSDocumentController.shared.addDocument(second)
                second.makeWindowControllers()
                let secondWindow = try #require(second.windowControllers.first?.window)
                secondWindow.isReleasedWhenClosed = false
                defer {
                    firstWindow.close()
                    first.close()
                    secondWindow.close()
                    second.close()
                }
                let secondPath = secondDirectory.path(percentEncoded: false)

                firstWindow.orderOut(nil)
                secondWindow.orderOut(nil)
                await MergeAutomation.perform("focusWorkspace:\(secondPath)")
                #expect(secondWindow.isVisible)
                #expect(firstWindow.isVisible == false)

                secondWindow.orderOut(nil)
                await MergeAutomation.perform("target:\(secondPath)")
                await MergeAutomation.perform("focusWorkspace:")
                #expect(secondWindow.isVisible)
                #expect(firstWindow.isVisible == false)
                await MergeAutomation.perform("target:")
            }
        }
    }

    @Test
    func dumpWithoutOpenWindowsReportsTheEmptyState() async throws {
        try await withSession { session in
            await MergeAutomation.perform("target:\(session.path)")
            MergeAutomation.registerBanner(path: nil, action: nil)

            let lines = try await dumpLines(session)

            #expect(value("target", in: lines) == session.path)
            #expect(value("workspace", in: lines) == session.path)
            #expect(value("documents", in: lines)?.contains(session.path) == true)
            #expect(value("banner.path", in: lines) == "")
            #expect(value("banner.action", in: lines) == "0")
            #expect(value("conflicts.open", in: lines) == "0")
            #expect(value("revisions.open", in: lines) == "0")
        }
    }

    @Test
    func dumpDescribesTheConflictsDialogAndTheRevisionsWindow() async throws {
        try await withSession { session in
            let conflicts = try await openConflicts(session)
            await MergeAutomation.perform("select:\(Self.configPath)")
            MergeAutomation.registerBanner(path: Self.configPath) {}
            let revisions = try await openRevisions(session)
            let merge = try #require(revisions.merge)
            _ = conflicts

            let lines = try await dumpLines(session)

            #expect(value("target", in: lines) == session.path)
            #expect(value("banner.path", in: lines) == Self.configPath)
            #expect(value("banner.action", in: lines) == "1")
            #expect(value("windowTitles", in: lines)?.contains("Conflicts") == true)

            #expect(value("conflicts.open", in: lines) == "1")
            #expect(value("conflicts.summary", in: lines) == Self.mergeSummary)
            #expect(value("conflicts.error", in: lines) == "")
            #expect(value("conflicts.busy", in: lines) == "0")
            #expect(value("conflicts.primary", in: lines) == Self.configPath)
            #expect(value("conflicts.selected", in: lines) == Self.configPath)
            #expect(value("conflicts.count", in: lines) == "2")
            #expect(values("conflicts.entry", in: lines) == [
                "app/config.txt|Modified|Modified",
                "docs/notes.txt|Modified|Modified"
            ])
            #expect(value("conflicts.yoursHeader", in: lines)?.contains("main") == true)
            #expect(value("conflicts.theirsHeader", in: lines)?.contains("feature") == true)

            #expect(value("revisions.open", in: lines) == "1")
            #expect(value("revisions.path", in: lines) == Self.configPath)
            #expect(value("revisions.title", in: lines) == "Merge Revisions for app/config.txt")
            #expect(value("revisions.summary", in: lines) == revisions.summary)
            #expect(value("revisions.error", in: lines) == "")
            #expect(value("revisions.valid", in: lines) == "1")
            #expect(value("revisions.edited", in: lines) == "0")
            #expect(value("revisions.loading", in: lines) == "0")
            #expect(value("revisions.leftTitle", in: lines) == "Your version, branch main")
            #expect(value("revisions.rightTitle", in: lines) == "Theirs, branch feature")
            #expect(value("revisions.conflicts", in: lines) == "1")
            #expect(value("revisions.changes", in: lines) == "2")
            #expect(values("revisions.block", in: lines).count == merge.blocks.count)
            #expect(values("revisions.block", in: lines).contains { $0.hasSuffix("|conflict|unresolved|5-6") })
            #expect(value("revisions.nonConflictingLeft", in: lines) == "1")
            #expect(value("revisions.nonConflictingAll", in: lines) == "1")
            #expect(value("revisions.nonConflictingRight", in: lines) == "1")
            #expect(value("revisions.result", in: lines) ==
                    "alpha\\nbeta-main\\ngamma\\ndelta\\nepsilon\\nzeta\\neta\\ntheta\\niota\\nkappa\\nfeature-added\\nlambda\\n")
            #expect(value("revisions.left", in: lines)?.contains("zeta-main") == true)
            #expect(value("revisions.right", in: lines)?.contains("zeta-feature") == true)
        }
    }

    @Test
    func dumpReportsEditedAndResolvedRevisionState() async throws {
        try await withSession { session in
            let model = try await openRevisions(session)
            let blockID = try conflictBlockID(model)
            await MergeAutomation.perform("resolve:\(blockID):right")
            await MergeAutomation.perform("editResult:one\\ntwo\\\\n")

            let lines = try await dumpLines(session)

            #expect(value("revisions.edited", in: lines) == "1")
            #expect(value("revisions.conflicts", in: lines) == "0")
            #expect(value("revisions.result", in: lines) == "one\\ntwo\\\\n")
            #expect(values("revisions.block", in: lines).contains { $0.hasSuffix("|conflict|right|5-6") })
        }
    }

    @Test
    func dumpWithoutADirectoryWritesIntoTheTemporaryDirectory() async throws {
        let output = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "merge.txt")
        defer { try? FileManager.default.removeItem(at: output) }
        try? FileManager.default.removeItem(at: output)
        await MergeAutomation.perform("target:/tmp/dreamder-dump-default")
        await MergeAutomation.perform("dump:")
        await MergeAutomation.perform("target:")

        let text = try String(contentsOf: output, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)

        #expect(value("target", in: lines) == "/tmp/dreamder-dump-default")
        #expect(value("banner.action", in: lines) != nil)
    }

    @Test
    func dumpReportsAnEmptyPrimaryPathWhenNothingIsSelected() async throws {
        try await withSession { session in
            let conflicts = try await openConflicts(session)
            conflicts.select(nil)

            let lines = try await dumpLines(session)

            #expect(value("conflicts.primary", in: lines) == "")
            #expect(value("conflicts.selected", in: lines) == "")
            #expect(value("conflicts.open", in: lines) == "1")
        }
    }
}
