import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct GitBlameHostedBlameCoverageTests {
    private static let fileName = "Blamed.txt"
    private static let workingText = "alpha\n\ncharlie2\ndelta2\necho2\n"
    private static let uncommittedInline = "You, uncommitted"

    private enum History {
        case committed
        case untracked
        case noRepository
    }

    private struct Commit {
        let hash: String
        let date: Date
    }

    @MainActor
    private final class DrawCounter {
        var count = 0
    }

    @MainActor
    private struct Session {
        let workspace: WorkspaceDocument?
        let git: GitMergeFixture
        let fixture: HostedSourceEditorFixture
        let hosted: HostedSourceEditor
        let blame: GitBlameCoordinator
        let controller: TextViewController
        let textView: TextView
        let commits: [Commit]

        var inlineView: GitBlameInlineView? {
            hosted.views(ofType: GitBlameInlineView.self).first
        }

        var annotation: GitBlameAnnotationView? {
            hosted.views(ofType: GitBlameAnnotationView.self).first
        }

        var inlineText: String? {
            inlineView?.text
        }

        var layoutManager: TextLayoutManager? {
            textView.layoutManager
        }

        func close() {
            hosted.close()
            workspace?.close()
        }

        func awaitBlame() async throws {
            try await eventually { inlineText != nil }
        }

        func awaitAnnotationLayout() async throws {
            try await eventually {
                hosted.window.layoutIfNeeded()
                guard let annotation, let scrollView = controller.scrollView else { return false }
                return annotation.frame.width > 0 && annotation.frame.size == scrollView.bounds.size
            }
        }

        func moveCaret(toLine line: Int) throws {
            let manager = try #require(layoutManager)
            let position = try #require(manager.textLineForIndex(line - 1))
            controller.setCursorPositions([CursorPosition(range: NSRange(location: position.range.location, length: 0))])
        }

        func typeAtStart() {
            textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "x")
        }

        func rewriteFirstLineOnDisk() throws {
            try git.write(GitBlameHostedBlameCoverageTests.fileName, "alpha-disk\n\ncharlie2\ndelta2\necho2\n")
        }

        func mouseDown() throws -> NSEvent {
            try #require(
                NSEvent.mouseEvent(
                    with: .leftMouseDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: hosted.window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: 1
                )
            )
        }
    }

    private static func inlineText(_ commit: Commit, author: String, summary: String) -> String {
        let date = GitBlameRelativeDate.string(for: commit.date)
        return summary.isEmpty ? "\(author), \(date)" : "\(author), \(date) • \(summary)"
    }

    private static func tooltip(_ commit: Commit, author: String, summary: String) -> String {
        let date = GitBlameRelativeDate.absoluteString(for: commit.date)
        let shortHash = String(commit.hash.prefix(8))
        return summary.isEmpty
            ? "\(author), \(date) — \(shortHash)"
            : "\(summary) — \(author), \(date) — \(shortHash)"
    }

    private static func commitHistory(_ git: GitMergeFixture) async throws -> [Commit] {
        let revisions: [(text: String, arguments: [String])] = [
            (
                "alpha\n\ncharlie\ndelta\necho\n",
                ["-m", "initial", "--date=2020-01-01T12:00:00+0000"]
            ),
            (
                "alpha\n\ncharlie2\ndelta\necho\n",
                ["-m", "second change", "--author=Other <other@dreamder.test>", "--date=2022-06-01T12:00:00+0000"]
            ),
            (
                "alpha\n\ncharlie2\ndelta2\necho\n",
                ["-m", "", "--allow-empty-message", "--date=2023-03-01T12:00:00+0000"]
            )
        ]
        var commits: [Commit] = []
        for revision in revisions {
            try git.write(fileName, revision.text)
            try await git.run("add", "-A")
            try await git.runAllowingFailure(["commit", "-q"] + revision.arguments)
            let stamp = try await git.run("show", "-s", "--format=%H %at", "HEAD")
            let parts = stamp.split(whereSeparator: \.isWhitespace)
            let hash = try #require(parts.first.map(String.init))
            let seconds = try #require(parts.last.flatMap { TimeInterval($0) })
            commits.append(Commit(hash: hash, date: Date(timeIntervalSince1970: seconds)))
        }
        return commits
    }

    private func openSession(
        in directory: URL,
        history: History = .committed,
        registerWorkspace: Bool = true,
        reloadDebounce: TimeInterval = 60,
        documentEditedChanges: AsyncStream<Bool>? = nil
    ) async throws -> Session {
        let git: GitMergeFixture
        var commits: [Commit] = []
        switch history {
        case .committed:
            git = try await GitMergeFixture(root: directory)
            commits = try await Self.commitHistory(git)
        case .untracked:
            git = try await GitMergeFixture(root: directory)
        case .noRepository:
            git = GitMergeFixture(existing: directory)
        }
        var workspace: WorkspaceDocument?
        if registerWorkspace {
            workspace = try HostedSourceEditorFixture.registerWorkspace(at: directory)
        }
        let fixture = try HostedSourceEditorFixture.make(
            in: directory,
            fileName: Self.fileName,
            typeIdentifier: "public.plain-text",
            contents: Self.workingText
        )
        let blame = GitBlameCoordinator(
            editorInstance: fixture.editorInstance,
            codeFile: fixture.document,
            reloadDebounce: reloadDebounce,
            documentEditedChanges: documentEditedChanges
        )
        let hosted = fixture.host(
            coordinators: [fixture.document.contentCoordinator, blame],
            size: NSSize(width: 900, height: 600)
        )
        try await eventually { hosted.controller?.textView?.window === hosted.window }
        let controller = try #require(hosted.controller)
        let textView = try #require(controller.textView)
        try await eventually {
            hosted.window.layoutIfNeeded()
            return (textView.layoutManager?.lineCount ?? 0) >= 6
                && hosted.views(ofType: GitBlameInlineView.self).count == 1
                && hosted.views(ofType: GitBlameAnnotationView.self).count == 1
        }
        return Session(
            workspace: workspace,
            git: git,
            fixture: fixture,
            hosted: hosted,
            blame: blame,
            controller: controller,
            textView: textView,
            commits: commits
        )
    }

    private func render(_ view: NSView) -> NSBitmapImageRep? {
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: representation)
        return representation
    }

    @Test
    func inlineBlameFollowsTheCaretThroughEveryCommitKind() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            try await session.awaitBlame()
            let expectations: [(line: Int, text: String)] = [
                (1, Self.inlineText(session.commits[0], author: "Merge", summary: "initial")),
                (3, Self.inlineText(session.commits[1], author: "Other", summary: "second change")),
                (4, Self.inlineText(session.commits[2], author: "Merge", summary: "")),
                (5, Self.uncommittedInline)
            ]

            for expectation in expectations {
                try session.moveCaret(toLine: expectation.line)
                try await eventually { session.inlineText == expectation.text }
            }
        }
    }

    @Test
    func emptySelectionNotificationsKeepTheCaretLine() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            try await session.awaitBlame()
            try session.moveCaret(toLine: 5)
            try await eventually { session.inlineText == Self.uncommittedInline }

            session.blame.textViewDidChangeSelection(controller: session.controller, newPositions: [])
            session.blame.textViewDidChangeSelection(
                controller: session.controller,
                newPositions: [CursorPosition(line: 0, column: 0)]
            )
            try await Task.sleep(for: .milliseconds(100))

            #expect(session.inlineText == Self.uncommittedInline)
        }
    }

    @Test
    func typingClearsTheBlameUntilItIsReloaded() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            try await session.awaitBlame()

            session.typeAtStart()

            try await eventually { session.inlineText == nil }
        }
    }

    @Test
    func typingReloadsTheBlameAfterTheDebounce() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory, reloadDebounce: 0.2)
            defer { session.close() }
            try await session.awaitBlame()
            try session.rewriteFirstLineOnDisk()

            session.typeAtStart()

            try await eventually { session.inlineText == Self.uncommittedInline }
        }
    }

    @Test
    func documentSavesReloadTheBlameButEditsDoNot() async throws {
        try await withTempDir { directory in
            let (changes, edited) = AsyncStream.makeStream(of: Bool.self)
            let session = try await openSession(in: directory, documentEditedChanges: changes)
            defer {
                edited.finish()
                session.close()
            }
            try await session.awaitBlame()
            try session.rewriteFirstLineOnDisk()
            session.typeAtStart()
            try await eventually { session.inlineText == nil }

            edited.yield(true)
            try await Task.sleep(for: .milliseconds(150))
            #expect(session.inlineText == nil)

            edited.yield(false)
            try await eventually { session.inlineText == Self.uncommittedInline }
        }
    }

    @Test
    func theDocumentsOwnEditedStateReloadsTheBlameOnceItIsClean() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            let document = session.fixture.document
            document.autosavingInPlace = { false }
            try await session.awaitBlame()
            try session.rewriteFirstLineOnDisk()
            session.typeAtStart()
            try await eventually { session.inlineText == nil }

            document.updateChangeCount(.changeDone)
            try await eventually { document.isEdited }
            #expect(session.inlineText == nil)

            document.updateChangeCount(.changeCleared)
            try await eventually { session.inlineText == Self.uncommittedInline }
        }
    }

    @Test
    func leavingAndReenteringTheRepositoryClearsAndReloadsTheBlame() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            let manager = try #require(session.workspace?.sourceControlManager)
            try await session.awaitBlame()

            manager.isGitRepository = false
            try await eventually { session.inlineText == nil }

            manager.isGitRepository = true
            try await eventually { session.inlineText != nil }
        }
    }

    @Test
    func aDeletedFileHasNoBlame() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            let manager = try #require(session.workspace?.sourceControlManager)
            try await session.awaitBlame()
            manager.isGitRepository = false
            try await eventually { session.inlineText == nil }
            try FileManager.default.removeItem(at: directory.appending(path: Self.fileName))

            manager.isGitRepository = true
            try await Task.sleep(for: .milliseconds(400))

            #expect(session.inlineText == nil)
        }
    }

    @Test
    func anUntrackedFileGainsBlameOnceItIsCommitted() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory, history: .untracked)
            defer { session.close() }
            let manager = try #require(session.workspace?.sourceControlManager)
            try await Task.sleep(for: .milliseconds(400))
            #expect(session.inlineText == nil)

            try await session.git.commit("late")
            manager.isGitRepository = false
            try await Task.sleep(for: .milliseconds(100))
            manager.isGitRepository = true

            try await eventually { session.inlineText?.hasSuffix("• late") == true }
        }
    }

    @Test
    func aWorkspaceWithoutARepositoryNeverLoadsBlame() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory, history: .noRepository)
            defer { session.close() }
            let manager = try #require(session.workspace?.sourceControlManager)

            try await Task.sleep(for: .milliseconds(400))

            #expect(manager.isGitRepository == false)
            #expect(session.inlineText == nil)
        }
    }

    @Test
    func anEditorOutsideAnyWorkspaceHasNoBlameAndIgnoresClicks() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory, history: .untracked, registerWorkspace: false)
            defer { session.close() }
            session.blame.toggleAnnotate()
            try await session.awaitAnnotationLayout()
            let annotation = try #require(session.annotation)

            try await Task.sleep(for: .milliseconds(300))
            annotation.mouseDown(with: try session.mouseDown())

            #expect(session.workspace == nil)
            #expect(session.inlineText == nil)
        }
    }

    @Test
    func annotateTogglesTheColumnVisibility() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            let annotation = try #require(session.annotation)
            #expect(session.blame.isAnnotating == false)
            #expect(annotation.isHidden)

            session.blame.toggleAnnotate()
            #expect(session.blame.isAnnotating)
            #expect(annotation.isHidden == false)

            session.blame.toggleAnnotate()
            #expect(session.blame.isAnnotating == false)
            #expect(annotation.isHidden)
        }
    }

    @Test
    func togglingAnnotateBeforeTheEditorAppearsOnlyFlipsTheMode() {
        let editor = EditorInstance(workspace: nil, file: CEWorkspaceFile(url: URL(filePath: "/fake/dir/file.swift")))
        let coordinator = GitBlameCoordinator(editorInstance: editor, codeFile: CodeFileDocument())

        coordinator.toggleAnnotate()
        #expect(coordinator.isAnnotating)
        coordinator.toggleAnnotate()
        #expect(coordinator.isAnnotating == false)
    }

    @Test
    func annotationColumnPaintsTheBlamedRows() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            session.blame.toggleAnnotate()
            try await session.awaitBlame()
            try await session.awaitAnnotationLayout()
            let annotation = try #require(session.annotation)

            let withRows = try #require(render(annotation))
            annotation.update(lines: [:])
            let withoutRows = try #require(render(annotation))

            #expect(HostedView.pixelsDiffer(withRows, withoutRows))
        }
    }

    @Test
    func annotationTooltipsDescribeTheCommitUnderThePointer() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            session.blame.toggleAnnotate()
            try await session.awaitBlame()
            try await session.awaitAnnotationLayout()
            let annotation = try #require(session.annotation)
            let manager = try #require(session.layoutManager)

            @MainActor func tooltip(forLine line: Int) throws -> String {
                let position = try #require(manager.textLineForIndex(line - 1))
                let point = session.textView.convert(
                    NSPoint(x: 10, y: position.yPos + position.height / 2),
                    to: annotation
                )
                return annotation.view(annotation, stringForToolTip: 0, point: point, userData: nil)
            }

            #expect(try tooltip(forLine: 1) == Self.tooltip(session.commits[0], author: "Merge", summary: "initial"))
            #expect(
                try tooltip(forLine: 3) == Self.tooltip(session.commits[1], author: "Other", summary: "second change")
            )
            #expect(try tooltip(forLine: 4) == Self.tooltip(session.commits[2], author: "Merge", summary: ""))
            let uncommitted = try tooltip(forLine: 5)
            #expect(uncommitted.contains("— You, "))
            #expect(uncommitted.hasSuffix(" — 00000000"))

            annotation.update(lines: [:])
            #expect(try tooltip(forLine: 1) == "")
        }
    }

    @Test
    func clickingTheAnnotationColumnRevealsTheGitToolWindow() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            let workspace = try #require(session.workspace)
            session.blame.toggleAnnotate()
            try await session.awaitAnnotationLayout()
            let annotation = try #require(session.annotation)
            let superview = try #require(annotation.superview)
            let leading = max(session.textView.textInsets.left, 0)
            let inside = annotation.convert(NSPoint(x: leading + 20, y: 20), to: superview)
            let outside = annotation.convert(
                NSPoint(x: leading + GitBlameAnnotationView.columnWidth + 40, y: 20),
                to: superview
            )
            #expect(annotation.hitTest(inside) === annotation)
            #expect(annotation.hitTest(outside) == nil)

            workspace.toolWindowManager.hide(.git)
            #expect(workspace.toolWindowManager.isVisible(.git) == false)
            annotation.mouseDown(with: try session.mouseDown())
            #expect(workspace.toolWindowManager.isVisible(.git))

            session.blame.toggleAnnotate()
            #expect(annotation.hitTest(inside) == nil)
        }
    }

    @Test
    func annotationFrameFollowsTheScrollViewOnTheNextRefresh() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            try await session.awaitAnnotationLayout()
            let annotation = try #require(session.annotation)
            let scrollView = try #require(session.controller.scrollView)
            annotation.frame = NSRect(x: 0, y: 0, width: 10, height: 10)

            session.blame.textViewDidChangeSelection(controller: session.controller, newPositions: [])

            try await eventually { annotation.frame.size == scrollView.bounds.size }
        }
    }

    @Test
    func inlineAnchorSitsOnTheLastCharacterOfTheCaretLine() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            try await session.awaitBlame()
            let inline = try #require(session.inlineView)
            let manager = try #require(session.layoutManager)
            let first = try #require(manager.textLineForIndex(0))
            let expected = manager.rectForOffset(first.range.max - 1)
            try session.moveCaret(toLine: 1)

            try await eventually { inline.anchorProvider?() == expected }
            #expect(expected != nil)
        }
    }

    @Test
    func inlineAnchorOfAnEmptyLastLineSitsAtItsStart() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            try await session.awaitBlame()
            let inline = try #require(session.inlineView)
            let manager = try #require(session.layoutManager)
            let lastLine = manager.lineCount
            let last = try #require(manager.textLineForIndex(lastLine - 1))
            #expect(last.range.length == 0)
            let expected = manager.rectForOffset(last.range.location)
            try session.moveCaret(toLine: lastLine)

            try await eventually { inline.anchorProvider?() == expected }
            #expect(expected != nil)
        }
    }

    @Test
    func inlineAnchorIsMissingPastTheLastLine() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            try await session.awaitBlame()
            let inline = try #require(session.inlineView)

            session.blame.textViewDidChangeSelection(
                controller: session.controller,
                newPositions: [CursorPosition(line: 99, column: 1)]
            )

            #expect(inline.anchorProvider?() == nil)
            try await eventually { session.inlineText == nil }
        }
    }

    @Test
    func inlineAnchorIsMissingOnceTheCoordinatorIsDestroyed() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            try await session.awaitBlame()
            let inline = try #require(session.inlineView)

            session.blame.destroy()

            #expect(inline.anchorProvider?() == nil)
            #expect(session.hosted.views(ofType: GitBlameInlineView.self).isEmpty)
            #expect(session.hosted.views(ofType: GitBlameAnnotationView.self).isEmpty)
        }
    }

    @Test
    func inlineViewPaintsTheCaretLineBlameAtItsAnchor() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            try await session.awaitBlame()
            let inline = try #require(session.inlineView)

            let painted = try #require(render(inline))
            inline.setText(nil)
            let bare = try #require(render(inline))

            #expect(HostedView.pixelsDiffer(painted, bare))
        }
    }

    @Test
    func inlayHintChangesRedrawTheInlineBlame() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            try await session.awaitBlame()
            let inline = try #require(session.inlineView)
            let counter = DrawCounter()
            let original = inline.anchorProvider
            inline.anchorProvider = {
                counter.count += 1
                return original?()
            }
            try await Task.sleep(for: .milliseconds(200))
            session.hosted.window.displayIfNeeded()
            inline.needsDisplay = false
            let baseline = counter.count

            NotificationCenter.default.post(
                name: InlayHintCoordinator.hintsDidChangeNotification,
                object: session.textView
            )

            try await eventually { inline.needsDisplay || counter.count > baseline }
        }
    }
}
