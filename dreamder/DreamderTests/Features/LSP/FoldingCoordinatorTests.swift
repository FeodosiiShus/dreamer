import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

private final class FoldingForeignAttachment: TextAttachment {
    let width: CGFloat = 10
    var isSelected = false

    func draw(in context: CGContext, rect: NSRect) {}

    func attachmentAction() -> TextAttachmentAction {
        .none
    }
}

@MainActor
private final class FoldingLoaderGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var isWaiting = false

    func wait() async {
        if released {
            return
        }
        isWaiting = true
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class FoldingLoaderProbe {
    var regions: [FoldRegion]
    var calls = 0
    var lastText: String?
    var lastTabWidth: Int?
    var onFirstCall: (() -> Void)?
    var gate: FoldingLoaderGate?

    init(regions: [FoldRegion]) {
        self.regions = regions
    }

    func load(_ text: String, _ tabWidth: Int) async -> [FoldRegion] {
        calls += 1
        lastText = text
        lastTabWidth = tabWidth
        if calls == 1 {
            onFirstCall?()
        }
        await gate?.wait()
        return regions
    }
}

@MainActor
private struct FoldingHostedSession {
    let fixture: HostedSourceEditorFixture
    let hosted: HostedSourceEditor
    let controller: TextViewController
    let textView: TextView
    let coordinator: FoldingCoordinator

    static func host(
        fixture: HostedSourceEditorFixture,
        coordinator: FoldingCoordinator,
        contents: String
    ) async throws -> FoldingHostedSession {
        let hosted = fixture.host(
            coordinators: [fixture.document.contentCoordinator, coordinator],
            size: NSSize(width: 900, height: 600)
        )
        try await eventually { hosted.controller?.textView != nil }
        let controller = try #require(hosted.controller)
        let textView = try #require(controller.textView)
        try await eventually { textView.textStorage.string == contents }
        return FoldingHostedSession(
            fixture: fixture,
            hosted: hosted,
            controller: controller,
            textView: textView,
            coordinator: coordinator
        )
    }

    static func open(
        in directory: URL,
        contents: String,
        regionLoader: FoldingCoordinator.RegionLoader? = nil,
        debounce: Duration = .milliseconds(20)
    ) async throws -> FoldingHostedSession {
        let fixture = try HostedSourceEditorFixture.make(
            in: directory,
            fileName: "Notes.txt",
            typeIdentifier: "public.plain-text",
            contents: contents
        )
        let coordinator = FoldingCoordinator(
            editorInstance: fixture.editorInstance,
            codeFile: fixture.document,
            clientProvider: { nil },
            debounce: debounce,
            regionLoader: regionLoader
        )
        return try await host(fixture: fixture, coordinator: coordinator, contents: contents)
    }

    func close() {
        hosted.close()
    }

    var foldAttachments: [AnyTextAttachment] {
        let everything = NSRange(location: 0, length: textView.textStorage.length + 1)
        return textView.layoutManager.attachments
            .getAttachmentsOverlapping(everything)
            .filter { $0.range.length > 0 }
    }

    var foldRanges: [NSRange] {
        foldAttachments.map(\.range)
    }

    var selections: [NSRange] {
        textView.selectionManager.textSelections.map(\.range)
    }

    func setCaret(_ offset: Int) {
        textView.selectionManager.setSelectedRange(NSRange(location: offset, length: 0))
    }

    func setSelection(_ range: NSRange) {
        textView.selectionManager.setSelectedRange(range)
    }
}

private let blockText = "func a() {\n    one\n    two\n}\nlet z = 1\n"
private let blockRegion = FoldRegion(startLine: 0, endLine: 2, kind: .block)
private let blockHidden = NSRange(location: 10, length: 16)

private let nestedText = "a\n  b\n    c\n    d\n  e\nf\n"
private let nestedOuter = FoldRegion(startLine: 0, endLine: 4, kind: .block)
private let nestedInner = FoldRegion(startLine: 1, endLine: 3, kind: .block)
private let nestedOuterHidden = NSRange(location: 1, length: 20)
private let nestedInnerHidden = NSRange(location: 5, length: 12)

private let linesText = (0..<10).map { "l\($0)\n" }.joined()

private func colorsMatch(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
    guard let left = lhs.usingColorSpace(.sRGB), let right = rhs.usingColorSpace(.sRGB) else { return false }
    return abs(left.redComponent - right.redComponent) < 0.01
        && abs(left.greenComponent - right.greenComponent) < 0.01
        && abs(left.blueComponent - right.blueComponent) < 0.01
        && abs(left.alphaComponent - right.alphaComponent) < 0.01
}

private func isDiscard(_ action: TextAttachmentAction) -> Bool {
    if case .discard = action {
        return true
    }
    return false
}

@MainActor
@Suite(.uiGate)
struct FoldingCoordinatorTests {
    @Test
    func collapseCodeBlockHidesTheBlockStartingAtTheCaretLineBehindAPlaceholder() async throws {
        try await withTempDir { directory in
            let session = try await FoldingHostedSession.open(in: directory, contents: blockText)
            defer { session.close() }
            session.setCaret(3)

            await session.coordinator.collapseCodeBlock()

            #expect(session.foldRanges == [blockHidden])
            let placeholder = try #require(session.foldAttachments.first?.attachment as? FoldPlaceholderAttachment)
            #expect(placeholder.region == blockRegion)
            #expect(session.coordinator.regions == [blockRegion])
            #expect(session.coordinator.collapsedRegions == [blockRegion])
            #expect(session.coordinator.isCollapsed(blockRegion))
            #expect(session.selections == [NSRange(location: 3, length: 0)])
        }
    }

    @Test
    func collapseCodeBlockMovesACaretInsideTheBlockToTheEndOfTheStartLine() async throws {
        try await withTempDir { directory in
            let session = try await FoldingHostedSession.open(in: directory, contents: blockText)
            defer { session.close() }
            session.setCaret(15)

            await session.coordinator.collapseCodeBlock()

            #expect(session.foldRanges == [blockHidden])
            #expect(session.selections == [NSRange(location: 10, length: 0)])
        }
    }

    @Test
    func collapseCodeBlockDoesNothingOutsideEveryBlockAndWhenTheBlockIsAlreadyCollapsed() async throws {
        try await withTempDir { directory in
            let session = try await FoldingHostedSession.open(in: directory, contents: blockText)
            defer { session.close() }
            session.setCaret(33)

            await session.coordinator.collapseCodeBlock()
            #expect(session.foldRanges.isEmpty)

            session.setCaret(3)
            await session.coordinator.collapseCodeBlock()
            await session.coordinator.collapseCodeBlock()
            #expect(session.foldRanges == [blockHidden])
        }
    }

    @Test
    func expandCodeBlockRestoresTheBlockStartingAtTheCaretLine() async throws {
        try await withTempDir { directory in
            let session = try await FoldingHostedSession.open(in: directory, contents: blockText)
            defer { session.close() }
            session.setCaret(15)
            await session.coordinator.collapseCodeBlock()

            session.coordinator.expandCodeBlock()

            #expect(session.foldRanges.isEmpty)
            #expect(session.coordinator.collapsedRegions.isEmpty)
            #expect(!session.coordinator.isCollapsed(blockRegion))
        }
    }

    @Test
    func withoutAnySelectionTheCaretCountsAsTheFirstLine() async throws {
        try await withTempDir { directory in
            let session = try await FoldingHostedSession.open(in: directory, contents: blockText)
            defer { session.close() }
            session.setCaret(3)
            await session.coordinator.collapseCodeBlock()
            session.textView.selectionManager.setSelectedRanges([])
            #expect(session.selections.isEmpty)

            session.coordinator.expandCodeBlock()

            #expect(session.foldRanges.isEmpty)
        }
    }

    @Test
    func expandCodeBlockLeavesBlocksCollapsedWhenTheCaretIsElsewhere() async throws {
        try await withTempDir { directory in
            let session = try await FoldingHostedSession.open(in: directory, contents: blockText)
            defer { session.close() }
            session.setCaret(3)
            await session.coordinator.collapseCodeBlock()
            session.setCaret(33)

            session.coordinator.expandCodeBlock()

            #expect(session.foldRanges == [blockHidden])
        }
    }

    @Test
    func repeatedCollapseWalksFromTheInnermostBlockOutwardAndExpandWalksBack() async throws {
        try await withTempDir { directory in
            let session = try await FoldingHostedSession.open(in: directory, contents: nestedText)
            defer { session.close() }
            session.setCaret(8)

            await session.coordinator.collapseCodeBlock()
            #expect(session.foldRanges == [nestedInnerHidden])
            #expect(session.selections == [NSRange(location: 5, length: 0)])

            await session.coordinator.collapseCodeBlock()
            #expect(session.foldRanges == [nestedOuterHidden, nestedInnerHidden])
            #expect(session.selections == [NSRange(location: 1, length: 0)])
            #expect(session.coordinator.collapsedRegions == [nestedOuter, nestedInner])

            session.coordinator.expandCodeBlock()
            #expect(session.foldRanges == [nestedInnerHidden])

            session.coordinator.expandCodeBlock()
            #expect(session.foldRanges == [nestedInnerHidden])

            session.setCaret(3)
            session.coordinator.expandCodeBlock()
            #expect(session.foldRanges.isEmpty)
        }
    }

    @Test
    func collapseAllFoldsEveryRegionAndExpandAllRestoresThem() async throws {
        try await withTempDir { directory in
            let session = try await FoldingHostedSession.open(in: directory, contents: nestedText)
            defer { session.close() }
            session.setCaret(8)

            await session.coordinator.collapseAll()

            #expect(session.foldRanges == [nestedOuterHidden, nestedInnerHidden])
            #expect(session.coordinator.collapsedRegions == [nestedOuter, nestedInner])
            #expect(session.selections == [NSRange(location: 1, length: 0)])

            await session.coordinator.collapseAll()
            #expect(session.foldRanges.count == 2)

            session.coordinator.expandAll()
            #expect(session.foldRanges.isEmpty)
            #expect(session.coordinator.collapsedRegions.isEmpty)
        }
    }

    @Test
    func selectionRestrictsCollapseAllAndExpandAllToTheRegionsInsideIt() async throws {
        try await withTempDir { directory in
            let session = try await FoldingHostedSession.open(in: directory, contents: nestedText)
            defer { session.close() }
            session.setSelection(NSRange(location: 2, length: 15))

            await session.coordinator.collapseAll()
            #expect(session.foldRanges == [nestedInnerHidden])

            await session.coordinator.collapseAll()
            #expect(session.foldRanges == [nestedInnerHidden])

            session.setCaret(0)
            await session.coordinator.collapseAll()
            #expect(session.foldRanges == [nestedOuterHidden, nestedInnerHidden])

            session.setSelection(NSRange(location: 2, length: 15))
            session.coordinator.expandAll()
            #expect(session.foldRanges == [nestedOuterHidden])

            session.setSelection(NSRange(location: 0, length: 1))
            session.coordinator.expandAll()
            #expect(session.foldRanges.isEmpty)
        }
    }

    @Test
    func collapseCommentsFoldsOnlyCommentRegions() async throws {
        try await withTempDir { directory in
            let probe = FoldingLoaderProbe(regions: [
                FoldRegion(startLine: 0, endLine: 2, kind: .comment),
                FoldRegion(startLine: 4, endLine: 6, kind: .region),
                FoldRegion(startLine: 8, endLine: 9, kind: .comment)
            ])
            let session = try await FoldingHostedSession.open(
                in: directory,
                contents: linesText,
                regionLoader: { text, tabWidth in await probe.load(text, tabWidth) }
            )
            defer { session.close() }

            await session.coordinator.collapseComments()
            await session.coordinator.collapseComments()

            #expect(session.foldRanges == [NSRange(location: 2, length: 6), NSRange(location: 26, length: 3)])
            #expect(session.coordinator.collapsedRegions == [probe.regions[0], probe.regions[2]])
        }
    }

    @Test
    func collapseCommentsIsANoOpWhenOnlyIndentationRegionsExist() async throws {
        try await withTempDir { directory in
            let session = try await FoldingHostedSession.open(in: directory, contents: blockText)
            defer { session.close() }

            await session.coordinator.collapseComments()

            #expect(session.foldRanges.isEmpty)
            #expect(session.coordinator.regions == [blockRegion])
        }
    }

    @Test
    func regionsAreLoadedLazilyOncePerTextVersionWithTheDocumentTextAndTabWidth() async throws {
        try await withTempDir { directory in
            let probe = FoldingLoaderProbe(regions: [blockRegion])
            let session = try await FoldingHostedSession.open(
                in: directory,
                contents: blockText,
                regionLoader: { text, tabWidth in await probe.load(text, tabWidth) }
            )
            defer { session.close() }
            #expect(probe.calls == 0)

            await session.coordinator.ensureRegions()
            await session.coordinator.ensureRegions()

            #expect(probe.calls == 1)
            #expect(probe.lastText == blockText)
            #expect(probe.lastTabWidth == session.controller.tabWidth)
            #expect(session.coordinator.regions == [blockRegion])
        }
    }

    @Test
    func textChangesBeforeTheFirstUseDoNotTriggerLoading() async throws {
        try await withTempDir { directory in
            let probe = FoldingLoaderProbe(regions: [blockRegion])
            let session = try await FoldingHostedSession.open(
                in: directory,
                contents: blockText,
                regionLoader: { text, tabWidth in await probe.load(text, tabWidth) }
            )
            defer { session.close() }

            session.coordinator.textViewDidChangeText(controller: session.controller)
            try await Task.sleep(for: .milliseconds(150))
            #expect(probe.calls == 0)

            await session.coordinator.ensureRegions()
            #expect(probe.calls == 1)
        }
    }

    @Test
    func textChangesRefreshLoadedRegionsOnceAfterTheDebounce() async throws {
        try await withTempDir { directory in
            let probe = FoldingLoaderProbe(regions: [blockRegion])
            let session = try await FoldingHostedSession.open(
                in: directory,
                contents: blockText,
                regionLoader: { text, tabWidth in await probe.load(text, tabWidth) }
            )
            defer { session.close() }
            await session.coordinator.ensureRegions()
            probe.regions = [nestedOuter]

            session.coordinator.textViewDidChangeText(controller: session.controller)
            session.coordinator.textViewDidChangeText(controller: session.controller)
            session.coordinator.textViewDidChangeText(controller: session.controller)

            try await eventually { probe.calls == 2 }
            try await Task.sleep(for: .milliseconds(150))
            #expect(probe.calls == 2)
            #expect(session.coordinator.regions == [nestedOuter])
        }
    }

    @Test
    func aTextChangeWhileLoadingDiscardsTheStaleResultAndLoadsAgain() async throws {
        try await withTempDir { directory in
            let probe = FoldingLoaderProbe(regions: [blockRegion])
            let session = try await FoldingHostedSession.open(
                in: directory,
                contents: blockText,
                regionLoader: { text, tabWidth in await probe.load(text, tabWidth) }
            )
            defer { session.close() }
            probe.onFirstCall = { [coordinator = session.coordinator, controller = session.controller] in
                coordinator.textViewDidChangeText(controller: controller)
            }

            await session.coordinator.ensureRegions()

            #expect(probe.calls == 2)
            #expect(session.coordinator.regions == [blockRegion])
        }
    }

    @Test
    func concurrentCallersShareOneLoad() async throws {
        try await withTempDir { directory in
            let probe = FoldingLoaderProbe(regions: [blockRegion])
            let gate = FoldingLoaderGate()
            probe.gate = gate
            let session = try await FoldingHostedSession.open(
                in: directory,
                contents: blockText,
                regionLoader: { text, tabWidth in await probe.load(text, tabWidth) }
            )
            defer { session.close() }
            let coordinator = session.coordinator

            let first = Task { @MainActor in await coordinator.ensureRegions() }
            try await eventually { gate.isWaiting }
            let second = Task { @MainActor in await coordinator.ensureRegions() }
            for _ in 0..<5 {
                await Task.yield()
            }
            gate.release()
            await first.value
            await second.value

            #expect(probe.calls == 1)
            #expect(coordinator.regions == [blockRegion])
        }
    }

    @Test
    func regionsOutsideTheDocumentAreSkippedWhenCollapsing() async throws {
        try await withTempDir { directory in
            let probe = FoldingLoaderProbe(regions: [FoldRegion(startLine: 0, endLine: 99, kind: .block), blockRegion])
            let session = try await FoldingHostedSession.open(
                in: directory,
                contents: blockText,
                regionLoader: { text, tabWidth in await probe.load(text, tabWidth) }
            )
            defer { session.close() }

            await session.coordinator.collapseAll()

            #expect(session.foldRanges == [blockHidden])
        }
    }

    @Test
    func editingTheFoldedTextDropsThePlaceholderAndEditsAboveShiftIt() async throws {
        try await withTempDir { directory in
            let session = try await FoldingHostedSession.open(in: directory, contents: blockText)
            defer { session.close() }
            session.setCaret(3)
            await session.coordinator.collapseCodeBlock()

            session.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "ab")
            session.coordinator.textViewDidChangeText(controller: session.controller)
            await session.coordinator.ensureRegions()

            #expect(session.foldRanges == [NSRange(location: 12, length: 16)])
            #expect(session.coordinator.collapsedRegions == [blockRegion])

            session.textView.replaceCharacters(in: NSRange(location: 20, length: 0), with: "X")
            session.coordinator.textViewDidChangeText(controller: session.controller)
            await session.coordinator.ensureRegions()

            #expect(session.foldRanges.isEmpty)
            #expect(session.coordinator.collapsedRegions.isEmpty)
        }
    }

    @Test
    func aForeignAttachmentOverTheRegionCountsAsFoldedAndIsRemovedByExpand() async throws {
        try await withTempDir { directory in
            let session = try await FoldingHostedSession.open(in: directory, contents: blockText)
            defer { session.close() }
            let foreign = FoldingForeignAttachment()
            session.textView.layoutManager.attachments.add(foreign, for: blockHidden)
            session.setCaret(3)
            await session.coordinator.ensureRegions()

            #expect(session.coordinator.isCollapsed(blockRegion))
            #expect(session.coordinator.collapsedRegions == [blockRegion])

            await session.coordinator.collapseCodeBlock()
            await session.coordinator.collapseAll()
            #expect(session.foldAttachments.count == 1)
            #expect(session.foldAttachments.first?.attachment === foreign)

            session.coordinator.expandCodeBlock()
            #expect(session.foldRanges.isEmpty)
            #expect(!session.coordinator.isCollapsed(blockRegion))
        }
    }

    @Test
    func aForeignAttachmentCrossingTheRegionEdgeBlocksCollapsingAndIsRemovedByExpandAll() async throws {
        try await withTempDir { directory in
            let session = try await FoldingHostedSession.open(in: directory, contents: blockText)
            defer { session.close() }
            session.textView.layoutManager.attachments.add(
                FoldingForeignAttachment(),
                for: NSRange(location: 8, length: 10)
            )
            session.setCaret(3)

            await session.coordinator.collapseCodeBlock()
            #expect(session.foldRanges == [NSRange(location: 8, length: 10)])
            #expect(session.coordinator.isCollapsed(blockRegion))

            session.coordinator.expandAll()
            #expect(session.foldRanges.isEmpty)
        }
    }

    @Test
    func aForeignAttachmentInsideTheRegionIsNotTheRegionsFold() async throws {
        try await withTempDir { directory in
            let session = try await FoldingHostedSession.open(in: directory, contents: blockText)
            defer { session.close() }
            session.textView.layoutManager.attachments.add(
                FoldingForeignAttachment(),
                for: NSRange(location: 12, length: 4)
            )
            session.setCaret(3)

            await session.coordinator.collapseCodeBlock()

            #expect(!session.coordinator.collapsedRegions.isEmpty)
            #expect(session.foldRanges == [blockHidden, NSRange(location: 12, length: 4)])
        }
    }

    @Test
    func emptyForeignAttachmentsAtTheFoldStartSurviveExpanding() async throws {
        try await withTempDir { directory in
            let session = try await FoldingHostedSession.open(in: directory, contents: blockText)
            defer { session.close() }
            session.setCaret(3)
            await session.coordinator.collapseCodeBlock()
            let marker = FoldingForeignAttachment()
            session.textView.layoutManager.attachments.add(marker, for: NSRange(location: 10, length: 0))

            session.coordinator.expandCodeBlock()

            #expect(session.foldRanges.isEmpty)
            let survivors = session.textView.layoutManager.attachments.getAttachmentsStartingIn(NSRange(location: 10, length: 1))
            #expect(survivors.count == 1)
            #expect(survivors.first?.attachment === marker)
        }
    }

    @Test
    func theFoldingCoordinatorRegistersItselfInTheEditorHub() async throws {
        try await withTempDir { directory in
            let session = try await FoldingHostedSession.open(in: directory, contents: blockText)
            defer { session.close() }

            let hub = EditorFeatureHubs.hub(for: session.fixture.editorInstance)

            #expect(hub.folding === session.coordinator)
        }
    }

    @Test
    func destroyingTheCoordinatorStopsRefreshesAndDisablesEveryCommand() async throws {
        try await withTempDir { directory in
            let probe = FoldingLoaderProbe(regions: [blockRegion])
            let session = try await FoldingHostedSession.open(
                in: directory,
                contents: blockText,
                regionLoader: { text, tabWidth in await probe.load(text, tabWidth) }
            )
            defer { session.close() }
            session.setCaret(3)
            await session.coordinator.collapseCodeBlock()
            session.coordinator.textViewDidChangeText(controller: session.controller)

            session.coordinator.destroy()
            try await Task.sleep(for: .milliseconds(150))

            #expect(probe.calls == 1)
            #expect(!session.coordinator.isCollapsed(blockRegion))
            #expect(session.coordinator.collapsedRegions.isEmpty)
            await session.coordinator.collapseCodeBlock()
            await session.coordinator.collapseAll()
            await session.coordinator.collapseComments()
            session.coordinator.expandCodeBlock()
            session.coordinator.expandAll()
            #expect(session.foldRanges == [blockHidden])
        }
    }

    @Test
    func clickingAPlaceholderDiscardsItSoTheRegionIsExpanded() async throws {
        try await withTempDir { directory in
            let session = try await FoldingHostedSession.open(in: directory, contents: blockText)
            defer { session.close() }
            session.setCaret(3)
            await session.coordinator.collapseCodeBlock()
            let folded = try #require(session.foldAttachments.first)

            #expect(isDiscard(folded.attachment.attachmentAction()))
            session.textView.layoutManager.attachments.remove(atOffset: folded.range.location)

            #expect(!session.coordinator.isCollapsed(blockRegion))
            #expect(session.coordinator.collapsedRegions.isEmpty)
        }
    }

    @Test
    func defaultClientLookupUsesTheLanguageServiceAndItsFoldingRanges() async throws {
        try await withTempDir { directory in
            let service = LSPService.shared
            let connection = ScriptedServerConnection()
            try connection.script(.textDocumentFoldingRange, FoldingTestServer.scriptedRanges)
            let server = try await FoldingTestServer.make(in: directory, connection: connection, provider: .optionA(true))
            let fixture = try HostedSourceEditorFixture.make(
                in: directory,
                fileName: "Notes.txt",
                typeIdentifier: "public.plain-text",
                contents: FoldingTestServer.sourceText
            )
            try await server.openDocument(fixture.document)
            let key = LSPService.ClientKey(.swift, directory.path() + "/")
            service.languageClients[key] = server
            defer { service.languageClients[key] = nil }
            let coordinator = FoldingCoordinator(editorInstance: fixture.editorInstance, codeFile: fixture.document)
            let session = try await FoldingHostedSession.host(
                fixture: fixture,
                coordinator: coordinator,
                contents: FoldingTestServer.sourceText
            )
            defer { session.close() }

            await coordinator.collapseComments()

            #expect(session.foldRanges == [NSRange(location: 26, length: 8)])
            #expect(coordinator.regions.map(\.kind) == [.imports, .comment, .block])
            #expect(connection.requestCount(.textDocumentFoldingRange) == 1)
        }
    }

    @Test
    func withoutARegisteredServerTheDefaultLookupFallsBackToIndentation() async throws {
        try await withTempDir { directory in
            let fixture = try HostedSourceEditorFixture.make(
                in: directory,
                fileName: "Notes.txt",
                typeIdentifier: "public.plain-text",
                contents: blockText
            )
            let coordinator = FoldingCoordinator(editorInstance: fixture.editorInstance, codeFile: fixture.document)
            let session = try await FoldingHostedSession.host(fixture: fixture, coordinator: coordinator, contents: blockText)
            defer { session.close() }
            session.setCaret(3)

            await coordinator.collapseCodeBlock()

            #expect(session.foldRanges == [blockHidden])
        }
    }
}

@MainActor
@Suite(.uiGate)
struct FoldPlaceholderAttachmentTests {
    private let region = FoldRegion(startLine: 0, endLine: 2, kind: .block)

    private func render(_ attachment: FoldPlaceholderAttachment, height: Int = 20) throws -> NSBitmapImageRep {
        let width = Int(attachment.width)
        let representation = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        let context = try #require(NSGraphicsContext(bitmapImageRep: representation))
        attachment.draw(in: context.cgContext, rect: NSRect(x: 0, y: 0, width: width, height: height))
        return representation
    }

    private func components(_ representation: NSBitmapImageRep, x: Int, y: Int) throws -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        let color = try #require(representation.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        return (color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent)
    }

    private var style: FoldPlaceholderStyle {
        FoldPlaceholderStyle(
            font: .systemFont(ofSize: 13),
            background: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1),
            foreground: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
            selectedBackground: NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1),
            selectedForeground: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        )
    }

    @Test
    func styleUsesTheThemeInvisiblesAndIslandsColors() {
        let font = NSFont.systemFont(ofSize: 12)
        let invisibles = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)

        let style = FoldPlaceholderStyle.make(font: font, invisibles: invisibles)

        #expect(style.font == font)
        #expect(colorsMatch(style.background, invisibles.withAlphaComponent(0.35)))
        #expect(colorsMatch(style.foreground, NSColor(Islands.editorForeground)))
        #expect(colorsMatch(style.selectedBackground, NSColor(Islands.selection)))
        #expect(colorsMatch(style.selectedForeground, NSColor(Islands.foreground)))
    }

    @Test
    func widthFitsTheEllipsisPlusPaddingAndMargins() {
        let attachment = FoldPlaceholderAttachment(region: region, style: style)

        #expect(attachment.region == region)
        #expect(!attachment.isSelected)
        #expect(attachment.width > FoldPlaceholderAttachment.horizontalPadding * 2 + FoldPlaceholderAttachment.margin * 2)
        #expect(attachment.width == attachment.width.rounded())
    }

    @Test
    func clickActionDiscardsThePlaceholder() {
        let attachment = FoldPlaceholderAttachment(region: region, style: style)

        #expect(isDiscard(attachment.attachmentAction()))
    }

    @Test
    func drawingPaintsARoundedPillWithTheEllipsisAndSwitchesColorsWhenSelected() throws {
        let attachment = FoldPlaceholderAttachment(region: region, style: style)
        let width = Int(attachment.width)

        let normal = try render(attachment)
        let outside = try components(normal, x: 0, y: 10)
        let pill = try components(normal, x: 5, y: 10)
        var hasGlyph = false
        for y in 3..<17 {
            for x in 8..<(width - 8) {
                let pixel = try components(normal, x: x, y: y)
                if pixel.g > 0.3 {
                    hasGlyph = true
                }
            }
        }

        attachment.isSelected = true
        let selected = try render(attachment)
        let selectedPill = try components(selected, x: 5, y: 10)

        #expect(outside.a < 0.01)
        #expect(pill.r > 0.9 && pill.g < 0.1 && pill.b < 0.1 && pill.a > 0.9)
        #expect(hasGlyph)
        #expect(selectedPill.b > 0.9 && selectedPill.r < 0.1 && selectedPill.a > 0.9)
    }
}
