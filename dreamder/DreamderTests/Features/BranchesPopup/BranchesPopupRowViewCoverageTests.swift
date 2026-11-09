import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class BranchesPopupRowCoverageRecorder {
    var activations = 0
    var toggles = 0
    var menus = 0
    var favorites = 0
}

@MainActor
@Suite(.uiGate)
struct BranchesPopupRowViewCoverageTests {
    private func makeRow(
        id: BranchesPopupItemID = .ref(.local, "feature/topic"),
        kind: BranchesPopupRowKind = .ref,
        title: String = "feature/topic",
        iconName: String? = "general/vcs",
        shortcut: String? = nil,
        detail: String? = nil,
        counters: String? = nil,
        matchRanges: [Range<Int>] = [],
        depth: Int = 1,
        isExpanded: Bool = false,
        isFavorite: Bool = false
    ) -> BranchesPopupRow {
        BranchesPopupRow(
            id: id,
            kind: kind,
            title: title,
            iconName: iconName,
            shortcut: shortcut,
            detail: detail,
            counters: counters,
            matchRanges: matchRanges,
            depth: depth,
            isExpanded: isExpanded,
            ref: nil,
            action: nil,
            ongoingAction: nil,
            isFavorite: isFavorite
        )
    }

    private func makeView(
        _ row: BranchesPopupRow,
        recorder: BranchesPopupRowCoverageRecorder,
        isSelected: Bool = false,
        isExpanded: Bool = false,
        isHovering: Bool = false
    ) -> BranchesPopupRowView {
        BranchesPopupRowView(
            row: row,
            isSelected: isSelected,
            isExpanded: isExpanded,
            isHovering: isHovering,
            onActivate: { recorder.activations += 1 },
            onToggle: { recorder.toggles += 1 },
            onOpenMenu: { recorder.menus += 1 },
            onToggleFavorite: { recorder.favorites += 1 }
        )
    }

    private func renderedSnapshot(_ view: BranchesPopupRowView) async throws -> NSBitmapImageRep? {
        let host = HostedViewFixture.host(size: NSSize(width: 380, height: 40)) { view }
        defer { host.close() }
        try await host.settle(.milliseconds(60))
        return host.snapshot()
    }

    @Test
    func tapOnSectionAndGroupRowsTogglesExpansion() {
        let recorder = BranchesPopupRowCoverageRecorder()

        makeView(makeRow(id: .section(.local), kind: .section, depth: 0), recorder: recorder).handleTap()
        makeView(makeRow(id: .group(.local, "feature"), kind: .group), recorder: recorder).handleTap()

        #expect(recorder.toggles == 2)
        #expect(recorder.activations == 0)
    }

    @Test
    func tapOnRefAndActionRowsActivates() {
        let recorder = BranchesPopupRowCoverageRecorder()

        makeView(makeRow(), recorder: recorder).handleTap()
        makeView(makeRow(id: .action(.commit), kind: .action, title: "Commit…", depth: 0), recorder: recorder).handleTap()

        #expect(recorder.activations == 2)
        #expect(recorder.toggles == 0)
    }

    @Test
    func tapOnSeparatorDoesNothing() {
        let recorder = BranchesPopupRowCoverageRecorder()

        makeView(makeRow(id: .separator("end"), kind: .separator, title: "", iconName: nil, depth: 0), recorder: recorder)
            .handleTap()

        #expect(recorder.activations == 0)
        #expect(recorder.toggles == 0)
        #expect(recorder.menus == 0)
        #expect(recorder.favorites == 0)
    }

    @Test
    func hoverCallbackAcceptsEnterAndExit() {
        let recorder = BranchesPopupRowCoverageRecorder()
        let view = makeView(makeRow(), recorder: recorder)

        view.setHovering(true)
        view.setHovering(false)

        #expect(recorder.activations == 0)
    }

    @Test
    func actionRowWithIconAndShortcutRenders() async throws {
        let recorder = BranchesPopupRowCoverageRecorder()
        let row = makeRow(
            id: .action(.commit),
            kind: .action,
            title: "Commit…",
            iconName: "vcs/commit",
            shortcut: "⌘K",
            depth: 0
        )

        let snapshot = try await renderedSnapshot(makeView(row, recorder: recorder))

        #expect(snapshot != nil)
    }

    @Test
    func rowWithoutIconRenders() async throws {
        let recorder = BranchesPopupRowCoverageRecorder()
        let row = makeRow(id: .section(.tags), kind: .section, title: "Tags", iconName: nil, depth: 0)

        let snapshot = try await renderedSnapshot(makeView(row, recorder: recorder, isExpanded: true))

        #expect(snapshot != nil)
    }

    @Test
    func sectionDisclosureDiffersBetweenExpandedAndCollapsed() async throws {
        let recorder = BranchesPopupRowCoverageRecorder()
        let row = makeRow(id: .section(.local), kind: .section, title: "Local", iconName: nil, depth: 0)

        let expanded = try await renderedSnapshot(makeView(row, recorder: recorder, isExpanded: true))
        let collapsed = try await renderedSnapshot(makeView(row, recorder: recorder, isExpanded: false))

        #expect(HostedView.pixelsDiffer(expanded, collapsed))
    }

    @Test
    func groupRowRendersDisclosureAtDepth() async throws {
        let recorder = BranchesPopupRowCoverageRecorder()
        let row = makeRow(id: .group(.local, "feature"), kind: .group, title: "feature", iconName: nil, depth: 1)

        let expanded = try await renderedSnapshot(makeView(row, recorder: recorder, isExpanded: true))
        let collapsed = try await renderedSnapshot(makeView(row, recorder: recorder, isExpanded: false))

        #expect(expanded != nil)
        #expect(HostedView.pixelsDiffer(expanded, collapsed))
    }

    @Test
    func selectionFillsTheRowBackground() async throws {
        let recorder = BranchesPopupRowCoverageRecorder()
        let row = makeRow()

        let plain = try await renderedSnapshot(makeView(row, recorder: recorder))
        let selected = try await renderedSnapshot(makeView(row, recorder: recorder, isSelected: true))

        #expect(HostedView.pixelsDiffer(plain, selected))
    }

    @Test
    func hoverShowsFavoriteStarOnNonFavoriteRefs() async throws {
        let recorder = BranchesPopupRowCoverageRecorder()
        let row = makeRow()

        let idle = try await renderedSnapshot(makeView(row, recorder: recorder))
        let hovered = try await renderedSnapshot(makeView(row, recorder: recorder, isHovering: true))
        let selectedHover = try await renderedSnapshot(
            makeView(row, recorder: recorder, isSelected: true, isHovering: true)
        )

        #expect(HostedView.pixelsDiffer(idle, hovered))
        #expect(selectedHover != nil)
    }

    @Test
    func favoriteRefShowsFilledStarWithoutHover() async throws {
        let recorder = BranchesPopupRowCoverageRecorder()
        let favorite = makeRow(isFavorite: true)
        let regular = makeRow()

        let favoriteSnapshot = try await renderedSnapshot(makeView(favorite, recorder: recorder))
        let regularSnapshot = try await renderedSnapshot(makeView(regular, recorder: recorder))

        #expect(HostedView.pixelsDiffer(favoriteSnapshot, regularSnapshot))
    }

    @Test
    func countersDetailAndShortcutAreRendered() async throws {
        let recorder = BranchesPopupRowCoverageRecorder()
        let bare = makeRow()
        let decorated = makeRow(detail: "origin/feature/topic", counters: "↑1 ↓2", isFavorite: true)

        let bareSnapshot = try await renderedSnapshot(makeView(bare, recorder: recorder))
        let decoratedSnapshot = try await renderedSnapshot(makeView(decorated, recorder: recorder))

        #expect(HostedView.pixelsDiffer(bareSnapshot, decoratedSnapshot))
    }

    @Test
    func matchRangesHighlightTitleCharacters() async throws {
        let recorder = BranchesPopupRowCoverageRecorder()
        let plain = makeRow(title: "feature/topic")
        let leading = makeRow(title: "feature/topic", matchRanges: [0..<2, 4..<5])
        let trailing = makeRow(title: "feature/topic", matchRanges: [8..<13])
        let middle = makeRow(title: "feature/topic", matchRanges: [3..<6])

        let plainSnapshot = try await renderedSnapshot(makeView(plain, recorder: recorder))
        let leadingSnapshot = try await renderedSnapshot(makeView(leading, recorder: recorder))
        let trailingSnapshot = try await renderedSnapshot(makeView(trailing, recorder: recorder))
        let middleSnapshot = try await renderedSnapshot(makeView(middle, recorder: recorder))

        #expect(HostedView.pixelsDiffer(plainSnapshot, leadingSnapshot))
        #expect(HostedView.pixelsDiffer(plainSnapshot, trailingSnapshot))
        #expect(HostedView.pixelsDiffer(plainSnapshot, middleSnapshot))
    }

    @Test
    func separatorAndDeepRefRowsRender() async throws {
        let recorder = BranchesPopupRowCoverageRecorder()
        let separator = makeRow(id: .separator("end"), kind: .separator, title: "", iconName: nil, depth: 0)
        let deep = makeRow(depth: 3)

        let separatorSnapshot = try await renderedSnapshot(makeView(separator, recorder: recorder))
        let deepSnapshot = try await renderedSnapshot(makeView(deep, recorder: recorder))

        #expect(separatorSnapshot != nil)
        #expect(deepSnapshot != nil)
    }
}
