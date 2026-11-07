import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

private final class FixedWidthAttachment: TextAttachment {
    let width: CGFloat = 10
    var isSelected = false

    func draw(in context: CGContext, rect: NSRect) {}

    func attachmentAction() -> TextAttachmentAction {
        .none
    }
}

@MainActor
@Suite(.serialized)
struct EditorDecorationBehaviorTests {
    private static let errorGroup = "dreamder.diagnostics.error"
    private static let warningGroup = "dreamder.diagnostics.warning"
    private static let trackedFileName = "Tracked.swift"
    private static let diagnosticsSource = "let alpha = 1\nlet beta = 2\nlet gamma = 3\nlet delta = 4\n"
    private static let gitSource = "alpha\nbravo\ncharlie\ndelta\necho\nfoxtrot\ngolf\nhotel\n"

    @MainActor
    private struct Session {
        let workspace: WorkspaceDocument
        let fixture: HostedSourceEditorFixture
        let hosted: HostedSourceEditor
        let textView: TextView
        let fileURL: URL

        func close() {
            hosted.close()
            workspace.close()
        }

        func replace(_ target: String, with replacement: String) throws {
            let range = (textView.string as NSString).range(of: target)
            try #require(range.location != NSNotFound, "missing \(target)")
            textView.replaceCharacters(in: range, with: replacement)
        }

        func replaceEverything(with text: String) {
            textView.replaceCharacters(in: NSRange(location: 0, length: textView.textStorage.length), with: text)
        }
    }

    private func awaitCondition(
        timeout: Duration = .seconds(20),
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(condition(), sourceLocation: sourceLocation)
    }

    private func openSession(
        in directory: URL,
        contents: String,
        commitFirst: Bool = false,
        extraFiles: [String: String] = [:],
        fileName: String? = nil,
        typeIdentifier: String = "public.swift-source",
        coordinators: (HostedSourceEditorFixture) -> [TextViewCoordinator]
    ) async throws -> Session {
        if commitFirst {
            let git = try GitMergeFixture(root: directory)
            try git.write(Self.trackedFileName, contents)
            for (name, text) in extraFiles {
                try git.write(name, text)
            }
            try git.commit("initial")
        }
        let workspace = try HostedSourceEditorFixture.registerWorkspace(at: directory)
        let fixtureFileName = fileName ?? (extraFiles.isEmpty ? Self.trackedFileName : "Fresh.swift")
        let fixture = try HostedSourceEditorFixture.make(
            in: directory,
            fileName: fixtureFileName,
            typeIdentifier: typeIdentifier,
            contents: contents
        )
        let hosted = fixture.host(coordinators: coordinators(fixture), size: NSSize(width: 900, height: 600))
        try await awaitCondition { hosted.controller?.textView != nil }
        let textView = try #require(hosted.controller?.textView)
        let fileURL = try #require(fixture.document.fileURL)
        return Session(workspace: workspace, fixture: fixture, hosted: hosted, textView: textView, fileURL: fileURL)
    }

    private func diagnosticsSession(in directory: URL) async throws -> Session {
        try await openSession(
            in: directory,
            contents: Self.diagnosticsSource,
            fileName: "Notes.txt",
            typeIdentifier: "public.plain-text"
        ) { fixture in
            [fixture.document.contentCoordinator, DiagnosticHighlightCoordinator(codeFile: fixture.document)]
        }
    }

    private func gitSession(
        in directory: URL,
        committed: Bool = true,
        extraFiles: [String: String] = [:],
        contents: String = EditorDecorationBehaviorTests.gitSource
    ) async throws -> Session {
        let session = try await openSession(
            in: directory,
            contents: contents,
            commitFirst: committed,
            extraFiles: extraFiles
        ) { fixture in
            [fixture.document.contentCoordinator, GitGutterCoordinator(codeFile: fixture.document)]
        }
        try await awaitCondition {
            !session.hosted.views(ofType: GitGutterMarkerView.self).isEmpty
        }
        try await Task.sleep(for: .milliseconds(2_000))
        return session
    }

    private func diagnostic(
        _ session: Session,
        _ severity: WorkspaceDiagnostic.Severity,
        line: Int,
        column: Int,
        endLine: Int? = nil,
        endColumn: Int
    ) -> WorkspaceDiagnostic {
        WorkspaceDiagnostic(
            fileURL: session.fileURL,
            startLine: line,
            startColumn: column,
            endLine: endLine ?? line,
            endColumn: endColumn,
            severity: severity,
            message: "message \(line):\(column)",
            source: nil,
            code: nil
        )
    }

    private func publish(_ diagnostics: [WorkspaceDiagnostic], in session: Session) {
        session.workspace.diagnosticsStore.replace(diagnostics, for: session.fileURL)
    }

    private func ranges(of group: String, in session: Session) -> [NSRange] {
        session.textView.emphasisManager?.getEmphases(for: group).map(\.range) ?? []
    }

    private func underlineColor(of emphasis: Emphasis) -> NSColor? {
        if case .underline(let color) = emphasis.style {
            return color
        }
        return nil
    }

    private func marker(in session: Session) throws -> GitGutterMarkerView {
        try #require(session.hosted.views(ofType: GitGutterMarkerView.self).first)
    }

    private func gutter(in session: Session) throws -> GutterView {
        try #require(session.hosted.views(ofType: GutterView.self).first)
    }

    private func hits(_ marker: GitGutterMarkerView, atY y: CGFloat) -> Bool {
        guard let superview = marker.superview else { return false }
        let local = NSPoint(x: marker.bounds.width - 6, y: y)
        return marker.hitTest(marker.convert(local, to: superview)) === marker
    }

    private func linesHit(
        by marker: GitGutterMarkerView,
        in session: Session,
        among lineNumbers: [Int],
        offsetFromTop: (CGFloat) -> CGFloat
    ) -> [Int] {
        lineNumbers.filter { number in
            guard let line = session.textView.layoutManager.textLineForIndex(number - 1) else { return false }
            return hits(marker, atY: line.yPos + offsetFromTop(line.height))
        }
    }

    private func linesHitAtMiddle(_ marker: GitGutterMarkerView, in session: Session, count: Int) -> [Int] {
        linesHit(by: marker, in: session, among: Array(1...count)) { height in height / 2 }
    }

    private func expectedMarkerFrame(in gutter: GutterView) -> NSRect {
        NSRect(
            x: gutter.bounds.width - GitGutterMarkerView.stripWidth,
            y: 0,
            width: GitGutterMarkerView.stripWidth,
            height: gutter.bounds.height
        )
    }

    @Test
    func errorsAndWarningsAreUnderlinedInSeparateGroupsWithSeverityColors() async throws {
        try await withTempDir { directory in
            let session = try await diagnosticsSession(in: directory)
            defer { session.close() }

            publish(
                [
                    diagnostic(session, .error, line: 1, column: 4, endColumn: 8),
                    diagnostic(session, .warning, line: 2, column: 4, endColumn: 9)
                ],
                in: session
            )
            try await awaitCondition {
                !ranges(of: Self.errorGroup, in: session).isEmpty && !ranges(of: Self.warningGroup, in: session).isEmpty
            }

            #expect(ranges(of: Self.errorGroup, in: session) == [NSRange(location: 18, length: 4)])
            #expect(ranges(of: Self.warningGroup, in: session) == [NSRange(location: 31, length: 5)])
            let errorEmphasis = session.textView.emphasisManager?.getEmphases(for: Self.errorGroup).first
            let warningEmphasis = session.textView.emphasisManager?.getEmphases(for: Self.warningGroup).first
            let errorColor = errorEmphasis.flatMap(underlineColor)
            let warningColor = warningEmphasis.flatMap(underlineColor)
            let expectedError = NSColor(Islands.errorForeground).usingColorSpace(.sRGB)
            let expectedWarning = NSColor(Islands.warningForeground).usingColorSpace(.sRGB)
            #expect(errorColor == expectedError)
            #expect(warningColor == expectedWarning)
            #expect(errorColor != warningColor)
        }
    }

    @Test
    func informationAndHintDiagnosticsAreNotUnderlined() async throws {
        try await withTempDir { directory in
            let session = try await diagnosticsSession(in: directory)
            defer { session.close() }

            publish(
                [
                    diagnostic(session, .information, line: 0, column: 0, endColumn: 3),
                    diagnostic(session, .hint, line: 1, column: 0, endColumn: 3),
                    diagnostic(session, .error, line: 2, column: 0, endColumn: 3)
                ],
                in: session
            )
            try await awaitCondition { !ranges(of: Self.errorGroup, in: session).isEmpty }

            #expect(ranges(of: Self.errorGroup, in: session) == [NSRange(location: 27, length: 3)])
            #expect(ranges(of: Self.warningGroup, in: session).isEmpty)
        }
    }

    @Test
    func multiLineDiagnosticSpansFromStartColumnToEndColumn() async throws {
        try await withTempDir { directory in
            let session = try await diagnosticsSession(in: directory)
            defer { session.close() }

            publish([diagnostic(session, .error, line: 0, column: 4, endLine: 2, endColumn: 5)], in: session)
            try await awaitCondition { !ranges(of: Self.errorGroup, in: session).isEmpty }

            #expect(ranges(of: Self.errorGroup, in: session) == [NSRange(location: 4, length: 28)])
        }
    }

    @Test
    func emptyDiagnosticRangeUnderlinesExactlyOneCharacter() async throws {
        try await withTempDir { directory in
            let session = try await diagnosticsSession(in: directory)
            defer { session.close() }

            publish([diagnostic(session, .warning, line: 1, column: 4, endColumn: 4)], in: session)
            try await awaitCondition { !ranges(of: Self.warningGroup, in: session).isEmpty }

            #expect(ranges(of: Self.warningGroup, in: session) == [NSRange(location: 18, length: 1)])
        }
    }

    @Test
    func endColumnPastTheDocumentIsClampedToTheTextLength() async throws {
        try await withTempDir { directory in
            let session = try await diagnosticsSession(in: directory)
            defer { session.close() }
            let textLength = session.textView.textStorage.length

            publish([diagnostic(session, .error, line: 3, column: 4, endColumn: 999)], in: session)
            try await awaitCondition { !ranges(of: Self.errorGroup, in: session).isEmpty }

            #expect(ranges(of: Self.errorGroup, in: session) == [NSRange(location: 45, length: textLength - 45)])
        }
    }

    @Test
    func diagnosticsOutsideTheDocumentProduceNoUnderline() async throws {
        try await withTempDir { directory in
            let session = try await diagnosticsSession(in: directory)
            defer { session.close() }

            publish(
                [
                    diagnostic(session, .error, line: 99, column: 0, endColumn: 4),
                    diagnostic(session, .error, line: 4, column: 0, endColumn: 4),
                    diagnostic(session, .error, line: -1, column: 0, endColumn: 4),
                    diagnostic(session, .error, line: 1, column: 0, endLine: 99, endColumn: 4),
                    diagnostic(session, .warning, line: 0, column: 0, endColumn: 3)
                ],
                in: session
            )
            try await awaitCondition { !ranges(of: Self.warningGroup, in: session).isEmpty }

            #expect(ranges(of: Self.errorGroup, in: session).isEmpty)
            #expect(ranges(of: Self.warningGroup, in: session) == [NSRange(location: 0, length: 3)])
        }
    }

    @Test
    func overlappingDiagnosticsKeepEveryUnderline() async throws {
        try await withTempDir { directory in
            let session = try await diagnosticsSession(in: directory)
            defer { session.close() }

            publish(
                [
                    diagnostic(session, .error, line: 1, column: 6, endColumn: 10),
                    diagnostic(session, .error, line: 1, column: 4, endColumn: 8),
                    diagnostic(session, .warning, line: 1, column: 5, endColumn: 7)
                ],
                in: session
            )
            try await awaitCondition { ranges(of: Self.errorGroup, in: session).count == 2 }

            #expect(
                ranges(of: Self.errorGroup, in: session)
                    == [NSRange(location: 18, length: 4), NSRange(location: 20, length: 4)]
            )
            #expect(ranges(of: Self.warningGroup, in: session) == [NSRange(location: 19, length: 2)])
        }
    }

    @Test
    func clearingDiagnosticsRemovesEveryUnderline() async throws {
        try await withTempDir { directory in
            let session = try await diagnosticsSession(in: directory)
            defer { session.close() }

            publish(
                [
                    diagnostic(session, .error, line: 1, column: 4, endColumn: 8),
                    diagnostic(session, .warning, line: 2, column: 4, endColumn: 9)
                ],
                in: session
            )
            try await awaitCondition {
                !ranges(of: Self.errorGroup, in: session).isEmpty && !ranges(of: Self.warningGroup, in: session).isEmpty
            }

            publish([], in: session)
            try await awaitCondition {
                ranges(of: Self.errorGroup, in: session).isEmpty && ranges(of: Self.warningGroup, in: session).isEmpty
            }

            session.workspace.diagnosticsStore.replace(
                [diagnostic(session, .error, line: 0, column: 0, endColumn: 3)],
                for: session.fileURL
            )
            try await awaitCondition { !ranges(of: Self.errorGroup, in: session).isEmpty }
            session.workspace.diagnosticsStore.clear(session.fileURL)
            try await awaitCondition { ranges(of: Self.errorGroup, in: session).isEmpty }
        }
    }

    @Test
    func replacingDiagnosticsReplacesInsteadOfAccumulatingUnderlines() async throws {
        try await withTempDir { directory in
            let session = try await diagnosticsSession(in: directory)
            defer { session.close() }

            publish([diagnostic(session, .error, line: 0, column: 0, endColumn: 3)], in: session)
            try await awaitCondition {
                ranges(of: Self.errorGroup, in: session) == [NSRange(location: 0, length: 3)]
            }
            publish([diagnostic(session, .error, line: 1, column: 0, endColumn: 3)], in: session)
            try await awaitCondition {
                ranges(of: Self.errorGroup, in: session) == [NSRange(location: 14, length: 3)]
            }

            #expect(ranges(of: Self.errorGroup, in: session) == [NSRange(location: 14, length: 3)])
        }
    }

    @Test
    func underlinesFollowTheirLinesAfterAnEditShiftsTheText() async throws {
        try await withTempDir { directory in
            let session = try await diagnosticsSession(in: directory)
            defer { session.close() }
            publish([diagnostic(session, .error, line: 1, column: 4, endColumn: 8)], in: session)
            try await awaitCondition {
                ranges(of: Self.errorGroup, in: session) == [NSRange(location: 18, length: 4)]
            }

            session.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "// header\n")
            try await awaitCondition {
                ranges(of: Self.errorGroup, in: session) == [NSRange(location: 14, length: 4)]
            }
            let underlined = (session.textView.string as NSString).substring(with: NSRange(location: 14, length: 4))

            #expect(underlined == "alph")
        }
    }

    @Test
    func editThatRemovesTheDiagnosticLineDropsItsUnderline() async throws {
        try await withTempDir { directory in
            let session = try await diagnosticsSession(in: directory)
            defer { session.close() }
            publish(
                [
                    diagnostic(session, .error, line: 3, column: 0, endColumn: 3),
                    diagnostic(session, .warning, line: 0, column: 0, endColumn: 3)
                ],
                in: session
            )
            try await awaitCondition { !ranges(of: Self.errorGroup, in: session).isEmpty }

            session.replaceEverything(with: "let alpha = 1\n")
            try await awaitCondition { ranges(of: Self.errorGroup, in: session).isEmpty }

            #expect(ranges(of: Self.warningGroup, in: session) == [NSRange(location: 0, length: 3)])
        }
    }

    @Test
    func gutterMarkerStripIsPinnedToTheRightEdgeOfTheGutter() async throws {
        try await withTempDir { directory in
            let session = try await gitSession(in: directory, committed: false)
            defer { session.close() }
            let marker = try marker(in: session)
            let gutter = try gutter(in: session)

            #expect(marker.superview === gutter)
            #expect(marker.frame == expectedMarkerFrame(in: gutter))
            #expect(marker.frame.width == GitGutterMarkerView.stripWidth)
        }
    }

    @Test
    func gutterMarkerFrameFollowsGutterWidthChanges() async throws {
        try await withTempDir { directory in
            let session = try await gitSession(in: directory, committed: false)
            defer { session.close() }
            let marker = try marker(in: session)
            let gutter = try gutter(in: session)
            let originalWidth = gutter.frame.width

            gutter.setFrameSize(NSSize(width: originalWidth + 40, height: gutter.frame.height))
            let widenedWidth = gutter.frame.width
            try await awaitCondition { marker.frame == expectedMarkerFrame(in: gutter) }

            #expect(widenedWidth != originalWidth)
            #expect(marker.frame.maxX == gutter.bounds.width)
            #expect(marker.frame.width == GitGutterMarkerView.stripWidth)
        }
    }

    @Test
    func editsAgainstHeadProduceAddedModifiedAndDeletedMarkersOnTheRightLines() async throws {
        try await withTempDir { directory in
            let session = try await gitSession(in: directory)
            defer { session.close() }
            let marker = try marker(in: session)
            #expect(marker.changes.isEmpty)

            try session.replace("bravo", with: "BRAVO!")
            try session.replace("delta\n", with: "delta\ndelta2\n")
            try session.replace("golf\n", with: "")
            try await awaitCondition { marker.changes.count == 3 }

            let expected = [
                GitLineChange(kind: .modified, oldLines: 2...2, newLines: 2...2, anchorLine: 2),
                GitLineChange(kind: .added, oldLines: nil, newLines: 5...5, anchorLine: 5),
                GitLineChange(kind: .deleted, oldLines: 7...7, newLines: nil, anchorLine: 7)
            ]
            #expect(marker.changes == expected)
            #expect(linesHitAtMiddle(marker, in: session, count: 8) == [2, 5])
            let boundaryHits = linesHit(by: marker, in: session, among: [1, 3, 4, 6, 7, 8]) { height in height - 1 }
            #expect(boundaryHits == [7])
        }
    }

    @Test
    func deletingTheFirstLineMarksTheTopBoundary() async throws {
        try await withTempDir { directory in
            let session = try await gitSession(in: directory)
            defer { session.close() }
            let marker = try marker(in: session)

            try session.replace("alpha\n", with: "")
            try await awaitCondition { !marker.changes.isEmpty }

            let expected = [GitLineChange(kind: .deleted, oldLines: 1...1, newLines: nil, anchorLine: 0)]
            #expect(marker.changes == expected)
            #expect(hits(marker, atY: 1))
            #expect(linesHitAtMiddle(marker, in: session, count: 7).isEmpty)
        }
    }

    @Test
    func consecutiveChangedLinesFormOneModifiedRange() async throws {
        try await withTempDir { directory in
            let session = try await gitSession(in: directory)
            defer { session.close() }
            let marker = try marker(in: session)

            try session.replace("charlie\ndelta\necho", with: "CHARLIE\nDELTA\nECHO")
            try await awaitCondition { !marker.changes.isEmpty }

            let expected = [GitLineChange(kind: .modified, oldLines: 3...5, newLines: 3...5, anchorLine: 3)]
            #expect(marker.changes == expected)
            #expect(linesHitAtMiddle(marker, in: session, count: 8) == [3, 4, 5])
        }
    }

    @Test
    func revertingTheFileToHeadClearsEveryMarker() async throws {
        try await withTempDir { directory in
            let session = try await gitSession(in: directory)
            defer { session.close() }
            let marker = try marker(in: session)
            try session.replace("bravo", with: "BRAVO!")
            try await awaitCondition { !marker.changes.isEmpty }
            #expect(linesHitAtMiddle(marker, in: session, count: 8) == [2])

            session.replaceEverything(with: Self.gitSource)
            try await awaitCondition { marker.changes.isEmpty }

            #expect(linesHitAtMiddle(marker, in: session, count: 8).isEmpty)
        }
    }

    @Test
    func untrackedFileIsMarkedAddedOnEveryLine() async throws {
        try await withTempDir { directory in
            let freshSource = "one\ntwo\nthree\nfour\n"
            let session = try await gitSession(
                in: directory,
                extraFiles: ["Committed.swift": "let committed = 1\n"],
                contents: freshSource
            )
            defer { session.close() }
            let marker = try marker(in: session)
            try await awaitCondition { !marker.changes.isEmpty }

            let lineCount = TextDiff.lines(in: freshSource).count
            let expected = [GitLineChange(kind: .added, oldLines: nil, newLines: 1...lineCount, anchorLine: 1)]
            #expect(marker.changes == expected)
            #expect(linesHitAtMiddle(marker, in: session, count: lineCount) == Array(1...lineCount))
        }
    }

    @Test
    func workspaceWithoutGitNeverShowsMarkers() async throws {
        try await withTempDir { directory in
            let session = try await gitSession(in: directory, committed: false)
            defer { session.close() }
            let marker = try marker(in: session)

            try session.replace("bravo", with: "BRAVO!")
            try await Task.sleep(for: .milliseconds(1_000))

            #expect(marker.changes.isEmpty)
            #expect(linesHitAtMiddle(marker, in: session, count: 8).isEmpty)
        }
    }

    @Test
    func destroyingTheGutterCoordinatorRemovesItsMarkerView() async throws {
        try await withTempDir { directory in
            let session = try await gitSession(in: directory, committed: false)
            defer { session.close() }
            let coordinator = try #require(session.hosted.coordinator(ofType: GitGutterCoordinator.self))
            let before = session.hosted.views(ofType: GitGutterMarkerView.self).count

            coordinator.destroy()
            let after = session.hosted.views(ofType: GitGutterMarkerView.self).count

            #expect(before == 1)
            #expect(after == 0)
        }
    }

    private func inlaySession(in directory: URL) async throws -> Session {
        try await openSession(
            in: directory,
            contents: Self.diagnosticsSource,
            fileName: "Notes.txt",
            typeIdentifier: "public.plain-text"
        ) { fixture in
            [fixture.document.contentCoordinator, InlayHintCoordinator(codeFile: fixture.document)]
        }
    }

    private func attachmentOffsets(in session: Session, inlayOnly: Bool) -> [Int] {
        let everything = NSRange(location: 0, length: session.textView.textStorage.length + 1)
        return session.textView.layoutManager.attachments.getAttachmentsStartingIn(everything)
            .filter { !inlayOnly || $0.attachment is InlayHintAttachment }
            .map(\.range.location)
    }

    @Test
    func destroyingTheInlayCoordinatorRemovesOnlyInlayAttachments() async throws {
        try await withTempDir { directory in
            let session = try await inlaySession(in: directory)
            defer { session.close() }
            let coordinator = try #require(session.hosted.coordinator(ofType: InlayHintCoordinator.self))
            let attachments = session.textView.layoutManager.attachments
            attachments.add(InlayHintAttachment(text: ": Int", fontSize: 11), for: NSRange(location: 5, length: 0))
            attachments.add(FixedWidthAttachment(), for: NSRange(location: 8, length: 0))
            attachments.add(InlayHintAttachment(text: ": String", fontSize: 11), for: NSRange(location: 20, length: 0))
            #expect(attachmentOffsets(in: session, inlayOnly: false) == [5, 8, 20])
            #expect(attachmentOffsets(in: session, inlayOnly: true) == [5, 20])

            coordinator.destroy()

            #expect(attachmentOffsets(in: session, inlayOnly: false) == [8])
            #expect(attachmentOffsets(in: session, inlayOnly: true).isEmpty)
        }
    }

    @Test
    func withoutALanguageServerForTheFileTypeNoInlayHintsAppearAndOtherAttachmentsSurvive() async throws {
        try await withTempDir { directory in
            let session = try await inlaySession(in: directory)
            defer { session.close() }
            session.textView.layoutManager.attachments.add(FixedWidthAttachment(), for: NSRange(location: 3, length: 0))

            session.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "// edit\n")
            try await Task.sleep(for: .milliseconds(1_000))

            #expect(attachmentOffsets(in: session, inlayOnly: true).isEmpty)
            #expect(attachmentOffsets(in: session, inlayOnly: false).count == 1)
        }
    }
}
