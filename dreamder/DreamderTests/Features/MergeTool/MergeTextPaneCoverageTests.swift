import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class MergeTextPaneRecorder {
    var chips: [MergePaneChip] = []
    var texts: [String] = []
}

@MainActor
@Observable
private final class MergeTextPaneProbeState {
    var content: MergePaneContent
    var revision: Int
    var isEditable: Bool

    init(content: MergePaneContent, revision: Int = 0, isEditable: Bool) {
        self.content = content
        self.revision = revision
        self.isEditable = isEditable
    }
}

private struct MergeTextPaneProbe: View {
    let state: MergeTextPaneProbeState
    let scrollSync: MergeScrollCoordinator
    let recorder: MergeTextPaneRecorder
    let paneID: String

    var body: some View {
        MergeTextPane(
            content: state.content,
            revision: state.revision,
            isEditable: state.isEditable,
            scrollSync: scrollSync,
            paneID: paneID,
            onChip: { recorder.chips.append($0) },
            onTextChange: { recorder.texts.append($0) }
        )
    }
}

private struct MergeTextPaneBareScrollProbe: View {
    let state: MergeTextPaneProbeState
    let scrollView: NSScrollView
    let recorder: MergeTextPaneRecorder

    var body: some View {
        MergeTextPane(
            content: state.content,
            revision: state.revision,
            isEditable: state.isEditable,
            scrollSync: MergeScrollCoordinator(),
            paneID: "bare",
            onChip: { recorder.chips.append($0) },
            onTextChange: { recorder.texts.append($0) },
            makeScrollView: { scrollView }
        )
    }
}

@MainActor
private func mergeTextPaneContent(
    lines: [String],
    styles: [MergeLineStyle]? = nil,
    chips: [Int: [MergePaneChip]] = [:]
) -> MergePaneContent {
    MergePaneContent(
        lines: lines,
        styles: styles ?? Array(repeating: .unchanged, count: lines.count),
        chips: chips
    )
}

@MainActor
private func mergeTextPaneBackground(of text: NSAttributedString, at index: Int) -> NSColor? {
    text.attribute(.backgroundColor, at: index, effectiveRange: nil) as? NSColor
}

@MainActor
private func mergeTextPaneTextView(in hosted: HostedView, paneID: String) -> NSTextView? {
    hosted.views(of: NSTextView.self).first { $0.identifier?.rawValue == "merge-pane-\(paneID)" }
}

@MainActor
@Suite(.uiGate)
struct MergeTextPaneRendererCoverageTests {
    @Test
    func plainRenderingJoinsLinesWithNewlinesAndNoGutter() {
        let content = mergeTextPaneContent(lines: ["alpha", "beta", "gamma"])
        let text = MergeTextPaneRenderer.attributedString(for: content, showsGutter: false)

        #expect(text.string == "alpha\nbeta\ngamma")
        #expect(mergeTextPaneBackground(of: text, at: 0) == nil)
    }

    @Test
    func emptyContentRendersNothing() {
        let text = MergeTextPaneRenderer.attributedString(for: .empty, showsGutter: true)
        #expect(text.length == 0)
    }

    @Test
    func everyLineStyleGetsItsBackground() {
        let content = mergeTextPaneContent(
            lines: ["same", "changed", "inserted", "conflict", "resolved"],
            styles: [.unchanged, .changed, .inserted, .conflict, .resolved]
        )
        let text = MergeTextPaneRenderer.attributedString(for: content, showsGutter: false)
        let string = text.string as NSString

        func background(of line: String) -> NSColor? {
            mergeTextPaneBackground(of: text, at: string.range(of: line).location)
        }

        #expect(background(of: "same") == nil)
        #expect(background(of: "changed") == NSColor(DiffColors.modified))
        #expect(background(of: "inserted") == NSColor(DiffColors.inserted))
        #expect(background(of: "conflict") == NSColor(hex: 0x5F3F3F))
        #expect(background(of: "resolved") == NSColor(DiffColors.inserted))
    }

    @Test
    func linesBeyondTheStyleListAreUnchanged() {
        let content = mergeTextPaneContent(lines: ["styled", "extra"], styles: [.changed])
        let text = MergeTextPaneRenderer.attributedString(for: content, showsGutter: false)
        let string = text.string as NSString

        #expect(mergeTextPaneBackground(of: text, at: 0) == NSColor(DiffColors.modified))
        #expect(mergeTextPaneBackground(of: text, at: string.range(of: "extra").location) == nil)
    }

    @Test
    func gutterShowsChipsAsLinksAndPadsOtherLines() throws {
        let chips = [
            MergePaneChip(kind: .acceptLeft, blockID: 7),
            MergePaneChip(kind: .ignore, blockID: 7)
        ]
        let content = mergeTextPaneContent(lines: ["first", "second"], chips: [0: chips])
        let text = MergeTextPaneRenderer.attributedString(for: content, showsGutter: true)

        #expect(text.string == "\u{00BB}\u{00D7} first\n   second")
        let acceptLink = try #require(text.attribute(.link, at: 0, effectiveRange: nil) as? NSURL)
        let ignoreLink = try #require(text.attribute(.link, at: 1, effectiveRange: nil) as? NSURL)
        #expect(acceptLink.absoluteString == "merge-block://left/7")
        #expect(ignoreLink.absoluteString == "merge-block://ignore/7")
        #expect(text.attribute(.link, at: 2, effectiveRange: nil) == nil)
        let secondLine = (text.string as NSString).range(of: "second").location
        #expect(text.attribute(.link, at: secondLine - 1, effectiveRange: nil) == nil)
    }

    @Test
    func gutterGrowsToTheWidestChipList() {
        let chips = [
            MergePaneChip(kind: .acceptRight, blockID: 1),
            MergePaneChip(kind: .ignore, blockID: 1),
            MergePaneChip(kind: .acceptLeft, blockID: 2)
        ]
        let content = mergeTextPaneContent(lines: ["row", "other"], chips: [1: chips])
        let text = MergeTextPaneRenderer.attributedString(for: content, showsGutter: true)

        #expect(text.string == "    row\n\u{00AB}\u{00D7}\u{00BB} other")
    }

    @Test
    func chipLinksRoundTripThroughURLAndNSURL() throws {
        let url = try #require(URL(string: "merge-block://left/3"))
        #expect(MergeTextPaneRenderer.chip(for: url) == MergePaneChip(kind: .acceptLeft, blockID: 3))
        let nsURL = try #require(NSURL(string: "merge-block://right/12"))
        #expect(MergeTextPaneRenderer.chip(for: nsURL) == MergePaneChip(kind: .acceptRight, blockID: 12))
        let ignore = try #require(URL(string: "merge-block://ignore/0"))
        #expect(MergeTextPaneRenderer.chip(for: ignore) == MergePaneChip(kind: .ignore, blockID: 0))
    }

    @Test
    func foreignOrMalformedLinksAreNotChips() throws {
        let other = try #require(URL(string: "https://left/1"))
        let unknownHost = try #require(URL(string: "merge-block://middle/1"))
        let badID = try #require(URL(string: "merge-block://left/first"))
        let noHost = try #require(URL(string: "merge-block:///1"))

        #expect(MergeTextPaneRenderer.chip(for: other) == nil)
        #expect(MergeTextPaneRenderer.chip(for: unknownHost) == nil)
        #expect(MergeTextPaneRenderer.chip(for: badID) == nil)
        #expect(MergeTextPaneRenderer.chip(for: noHost) == nil)
        #expect(MergeTextPaneRenderer.chip(for: "merge-block://left/1") == nil)
    }
}

@MainActor
@Suite(.uiGate)
struct MergeTextPaneCoverageTests {
    private func makePane(
        recorder: MergeTextPaneRecorder,
        isEditable: Bool,
        content: MergePaneContent = .empty
    ) -> MergeTextPane {
        MergeTextPane(
            content: content,
            revision: 0,
            isEditable: isEditable,
            scrollSync: MergeScrollCoordinator(),
            paneID: "unit",
            onChip: { recorder.chips.append($0) },
            onTextChange: { recorder.texts.append($0) }
        )
    }

    private func host(
        state: MergeTextPaneProbeState,
        scrollSync: MergeScrollCoordinator = MergeScrollCoordinator(),
        recorder: MergeTextPaneRecorder,
        paneID: String
    ) -> HostedView {
        HostedViewFixture.host(size: NSSize(width: 480, height: 320)) {
            MergeTextPaneProbe(state: state, scrollSync: scrollSync, recorder: recorder, paneID: paneID)
        }
    }

    @Test
    func readOnlyPaneIsConfiguredAndRendersWithGutter() async throws {
        let chips = [MergePaneChip(kind: .acceptLeft, blockID: 4)]
        let state = MergeTextPaneProbeState(
            content: mergeTextPaneContent(
                lines: ["one", "two"],
                styles: [.conflict, .unchanged],
                chips: [0: chips]
            ),
            isEditable: false
        )
        let hosted = host(state: state, recorder: MergeTextPaneRecorder(), paneID: "left")
        defer { hosted.close() }
        try await hosted.settle()

        let textView = try #require(mergeTextPaneTextView(in: hosted, paneID: "left"))
        #expect(textView.isEditable == false)
        #expect(textView.isSelectable)
        #expect(textView.isRichText == false)
        #expect(textView.allowsUndo)
        #expect(textView.string == "\u{00BB}  one\n   two")
        #expect(textView.textContainerInset == NSSize(width: 8, height: 6))
        #expect(textView.font == Islands.codeNSFont)
        #expect(textView.isAutomaticQuoteSubstitutionEnabled == false)
        #expect(textView.isAutomaticDashSubstitutionEnabled == false)
        #expect(textView.isAutomaticTextReplacementEnabled == false)
        #expect(textView.isAutomaticSpellingCorrectionEnabled == false)
        #expect(textView.isContinuousSpellCheckingEnabled == false)
        #expect(textView.isGrammarCheckingEnabled == false)
        let scrollView = try #require(textView.enclosingScrollView)
        #expect(scrollView.hasVerticalScroller)
        #expect(scrollView.hasHorizontalScroller == false)
        #expect(scrollView.autohidesScrollers)
        #expect(scrollView.borderType == .noBorder)
        #expect(hosted.renders())
    }

    @Test
    func editablePaneRendersWithoutGutterAndReportsEdits() async throws {
        let recorder = MergeTextPaneRecorder()
        let state = MergeTextPaneProbeState(content: mergeTextPaneContent(lines: ["abc", "def"]), isEditable: true)
        let hosted = host(state: state, recorder: recorder, paneID: "result")
        defer { hosted.close() }
        try await hosted.settle()

        let textView = try #require(mergeTextPaneTextView(in: hosted, paneID: "result"))
        #expect(textView.isEditable)
        #expect(textView.string == "abc\ndef")

        textView.insertText("Z", replacementRange: NSRange(location: 0, length: 0))

        #expect(recorder.texts == ["Zabc\ndef"])
    }

    @Test
    func updatesFollowTheModelOnlyWhenTheRevisionChanges() async throws {
        let recorder = MergeTextPaneRecorder()
        let state = MergeTextPaneProbeState(
            content: mergeTextPaneContent(lines: ["first"]),
            revision: 1,
            isEditable: true
        )
        let hosted = host(state: state, recorder: recorder, paneID: "result")
        defer { hosted.close() }
        try await hosted.settle()
        let textView = try #require(mergeTextPaneTextView(in: hosted, paneID: "result"))
        #expect(textView.string == "first")

        state.content = mergeTextPaneContent(lines: ["second"])
        try await hosted.settle()
        #expect(textView.string == "first")

        state.revision = 2
        try await eventually { textView.string == "second" }
        #expect(recorder.texts.isEmpty)
    }

    @Test
    func editablePaneKeepsTheCaretInsideTheNewText() async throws {
        let recorder = MergeTextPaneRecorder()
        let state = MergeTextPaneProbeState(
            content: mergeTextPaneContent(lines: ["a long first line"]),
            revision: 1,
            isEditable: true
        )
        let hosted = host(state: state, recorder: recorder, paneID: "result")
        defer { hosted.close() }
        try await hosted.settle()
        let textView = try #require(mergeTextPaneTextView(in: hosted, paneID: "result"))
        textView.setSelectedRange(NSRange(location: 12, length: 0))

        state.content = mergeTextPaneContent(lines: ["short"])
        state.revision = 2
        try await eventually { textView.string == "short" }

        #expect(textView.selectedRange() == NSRange(location: 5, length: 0))

        textView.setSelectedRange(NSRange(location: 2, length: 0))
        state.content = mergeTextPaneContent(lines: ["another text"])
        state.revision = 3
        try await eventually { textView.string == "another text" }
        #expect(textView.selectedRange() == NSRange(location: 2, length: 0))
    }

    @Test
    func editabilityFollowsTheModel() async throws {
        let recorder = MergeTextPaneRecorder()
        let state = MergeTextPaneProbeState(content: mergeTextPaneContent(lines: ["x"]), isEditable: false)
        let hosted = host(state: state, recorder: recorder, paneID: "pane")
        defer { hosted.close() }
        try await hosted.settle()
        let textView = try #require(mergeTextPaneTextView(in: hosted, paneID: "pane"))
        #expect(textView.isEditable == false)

        state.isEditable = true
        try await eventually { textView.isEditable }

        state.isEditable = false
        try await eventually { textView.isEditable == false }
    }

    @Test
    func clickingAChipLinkReportsTheChip() async throws {
        let recorder = MergeTextPaneRecorder()
        let chips = [
            MergePaneChip(kind: .acceptLeft, blockID: 9),
            MergePaneChip(kind: .ignore, blockID: 9)
        ]
        let state = MergeTextPaneProbeState(
            content: mergeTextPaneContent(lines: ["conflict"], styles: [.conflict], chips: [0: chips]),
            isEditable: false
        )
        let hosted = host(state: state, recorder: recorder, paneID: "left")
        defer { hosted.close() }
        try await hosted.settle()
        let textView = try #require(mergeTextPaneTextView(in: hosted, paneID: "left"))
        let accept = try #require(NSURL(string: "merge-block://left/9"))
        let ignore = try #require(NSURL(string: "merge-block://ignore/9"))

        textView.clicked(onLink: accept, at: 0)
        textView.clicked(onLink: ignore, at: 1)

        #expect(recorder.chips == chips)
    }

    @Test
    func panesRegisterTheirScrollViewsForSyncing() async throws {
        let recorder = MergeTextPaneRecorder()
        let scrollSync = MergeScrollCoordinator()
        let lines = (0..<400).map { "line \($0)" }
        let stateA = MergeTextPaneProbeState(content: mergeTextPaneContent(lines: lines), isEditable: false)
        let stateB = MergeTextPaneProbeState(content: mergeTextPaneContent(lines: lines), isEditable: true)
        let hosted = HostedViewFixture.host(size: NSSize(width: 600, height: 300)) {
            HStack(spacing: 0) {
                MergeTextPaneProbe(state: stateA, scrollSync: scrollSync, recorder: recorder, paneID: "a")
                MergeTextPaneProbe(state: stateB, scrollSync: scrollSync, recorder: recorder, paneID: "b")
            }
        }
        defer { hosted.close() }
        try await hosted.settle()
        let first = try #require(mergeTextPaneTextView(in: hosted, paneID: "a")?.enclosingScrollView)
        let second = try #require(mergeTextPaneTextView(in: hosted, paneID: "b")?.enclosingScrollView)

        first.contentView.scroll(to: NSPoint(x: 0, y: 100))
        first.reflectScrolledClipView(first.contentView)

        try await eventually { second.contentView.bounds.origin.y > 0 }
    }

    @Test
    func scrollViewWithoutATextViewIsConfiguredAndLeftUntouchedOnUpdates() async throws {
        let recorder = MergeTextPaneRecorder()
        let bare = NSScrollView()
        let state = MergeTextPaneProbeState(content: mergeTextPaneContent(lines: ["never shown"]), isEditable: true)
        let hosted = HostedViewFixture.host(size: NSSize(width: 480, height: 320)) {
            MergeTextPaneBareScrollProbe(state: state, scrollView: bare, recorder: recorder)
        }
        defer { hosted.close() }
        try await hosted.settle()

        #expect(hosted.views(of: NSScrollView.self).contains { $0 === bare })
        #expect(bare.hasVerticalScroller)
        #expect(bare.hasHorizontalScroller == false)
        #expect(bare.borderType == .noBorder)
        #expect(bare.documentView == nil)

        state.revision = 1
        state.isEditable = false
        try await hosted.settle()

        #expect(bare.documentView == nil)
        #expect(hosted.views(of: NSTextView.self).isEmpty)
        #expect(recorder.texts.isEmpty)
        #expect(recorder.chips.isEmpty)
    }

    @Test
    func coordinatorWithoutATextViewIgnoresRenders() {
        let recorder = MergeTextPaneRecorder()
        let pane = makePane(recorder: recorder, isEditable: true)
        let coordinator = MergeTextPane.Coordinator(parent: pane)

        coordinator.render(content: mergeTextPaneContent(lines: ["lost"]), revision: 1, editable: true)

        let textView = NSTextView()
        coordinator.textView = textView
        coordinator.render(content: mergeTextPaneContent(lines: ["same revision"]), revision: 1, editable: true)
        #expect(textView.string.isEmpty)

        coordinator.render(content: mergeTextPaneContent(lines: ["next revision"]), revision: 2, editable: true)
        #expect(textView.string == "next revision")
    }

    @Test
    func coordinatorRendersTheGutterForReadOnlyPanes() {
        let recorder = MergeTextPaneRecorder()
        let pane = makePane(recorder: recorder, isEditable: false)
        let coordinator = MergeTextPane.Coordinator(parent: pane)
        let textView = NSTextView()
        coordinator.textView = textView

        coordinator.render(content: mergeTextPaneContent(lines: ["readonly"]), revision: 1, editable: false)

        #expect(textView.string == "   readonly")
    }

    @Test
    func coordinatorRejectsLinksThatAreNotChips() throws {
        let recorder = MergeTextPaneRecorder()
        let pane = makePane(recorder: recorder, isEditable: false)
        let coordinator = MergeTextPane.Coordinator(parent: pane)
        let textView = NSTextView()
        let foreign = try #require(URL(string: "https://example.com"))
        let chip = try #require(URL(string: "merge-block://right/5"))

        #expect(coordinator.textView(textView, clickedOnLink: foreign, at: 0) == false)
        #expect(recorder.chips.isEmpty)
        #expect(coordinator.textView(textView, clickedOnLink: chip, at: 0))
        #expect(recorder.chips == [MergePaneChip(kind: .acceptRight, blockID: 5)])
    }

    @Test
    func coordinatorReportsTextChangesOnlyFromEditablePanes() {
        let recorder = MergeTextPaneRecorder()
        let textView = NSTextView()
        textView.string = "edited"

        let editable = MergeTextPane.Coordinator(parent: makePane(recorder: recorder, isEditable: true))
        editable.textDidChange(Notification(name: NSText.didChangeNotification, object: NSObject()))
        #expect(recorder.texts.isEmpty)
        editable.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        #expect(recorder.texts == ["edited"])

        let readOnly = MergeTextPane.Coordinator(parent: makePane(recorder: recorder, isEditable: false))
        readOnly.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        #expect(recorder.texts == ["edited"])
    }
}
