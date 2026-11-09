import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct RecentLocationsViewTests {
    private func row(_ preview: RecentLocationsPreview, directory: String = "Sources/App") -> RecentLocationsRow {
        RecentLocationsRow(
            place: EditorPlace(fileURL: URL(filePath: "/work/app/Sources/App/Main.swift"), line: 7, column: 1),
            fileName: "Main.swift",
            fileIconName: IntelliJIcon.fileIcon(for: "Main.swift"),
            relativeDirectory: directory,
            preview: preview
        )
    }

    private var sampleLines: RecentLocationsPreview {
        .lines([
            RecentLocationsPreviewLine(number: 5, text: "func alpha() {", isCaretLine: false),
            RecentLocationsPreviewLine(number: 6, text: "", isCaretLine: false),
            RecentLocationsPreviewLine(number: 7, text: "    beta()", isCaretLine: true)
        ])
    }

    @Test
    func rowViewRendersEveryPreviewVariantSelectedAndNot() async throws {
        let variants: [RecentLocationsPreview] = [.pending, .emptyFile, sampleLines]
        for selected in [false, true] {
            let hosted = HostedViewFixture.host(size: NSSize(width: 640, height: 260)) {
                VStack(spacing: 0) {
                    ForEach(Array(variants.enumerated()), id: \.offset) { _, preview in
                        RecentLocationsRowView(row: row(preview), isSelected: selected, onSelect: {}, onOpen: {})
                    }
                    RecentLocationsRowView(row: row(.pending, directory: ""), isSelected: selected, onSelect: {}, onOpen: {})
                }
            }
            defer { hosted.close() }

            try await hosted.settle(.milliseconds(100))

            #expect(hosted.renders())
        }
    }

    @Test
    func viewRendersListEmptyAndChangedStates() async throws {
        try await withTempDir { directory in
            let fixture = try RecentLocationsPopupFixture.make(in: directory, names: ["a.txt", "empty.txt", "b.txt"])
            defer { fixture.workspace.close() }
            try "".write(to: directory.appending(path: "empty.txt"), atomically: true, encoding: .utf8)
            fixture.tracker.recordNavigation(from: fixture.place("a.txt", line: 5))
            fixture.tracker.recordNavigation(from: fixture.place("empty.txt", line: 1))
            let slowLoader: RecentLocationsViewModel.TextLoader = { urls in
                try? await Task.sleep(for: .milliseconds(150))
                var texts: [URL: String] = [:]
                for url in urls {
                    texts[url] = url.lastPathComponent == "empty.txt" ? "" : "alpha\nbeta\ngamma\ndelta\nepsilon"
                }
                return texts
            }
            let model = RecentLocationsViewModel(tracker: fixture.tracker, workspace: fixture.workspace, loadTexts: slowLoader)
            let hosted = HostedViewFixture.host(size: NSSize(width: 700, height: 530)) {
                RecentLocationsView(model: model)
            }
            defer { hosted.close() }

            try await hosted.settle(.milliseconds(50))
            #expect(hosted.renders())
            let pending = hosted.snapshot()

            try await eventually { model.rows.allSatisfy { $0.preview != .pending } }
            try await hosted.settle(.milliseconds(100))
            #expect(hosted.renders())
            #expect(HostedView.pixelsDiffer(pending, hosted.snapshot()))

            model.moveSelection(1)
            try await hosted.settle(.milliseconds(100))
            #expect(model.selectedIndex == 1)
            #expect(hosted.renders())

            model.showChangedOnly = true
            try await hosted.settle(.milliseconds(100))
            #expect(model.rows.isEmpty)
            #expect(hosted.renders())
        }
    }

    @Test
    func viewRendersTheChangedList() async throws {
        try await withTempDir { directory in
            let fixture = try RecentLocationsPopupFixture.make(in: directory, names: ["a.txt"])
            defer { fixture.workspace.close() }
            fixture.tracker.recordChange(fixture.place("a.txt", line: 9))
            let model = RecentLocationsViewModel(
                tracker: fixture.tracker,
                workspace: fixture.workspace,
                showChangedOnly: true,
                loadTexts: { urls in Dictionary(uniqueKeysWithValues: urls.map { ($0, "one\ntwo") }) }
            )
            let hosted = HostedViewFixture.host(size: NSSize(width: 700, height: 530)) {
                RecentLocationsView(model: model)
            }
            defer { hosted.close() }

            try await eventually { model.rows.allSatisfy { $0.preview != .pending } }
            try await hosted.settle(.milliseconds(100))

            #expect(model.rows.count == 1)
            #expect(model.title == "Recently Edited Locations")
            #expect(hosted.renders())
        }
    }

    @Test
    func rowBackgroundFollowsSelectionThenHover() {
        #expect(RecentLocationsRowView.backgroundColor(isSelected: true, isHovering: true) == Islands.selection)
        #expect(RecentLocationsRowView.backgroundColor(isSelected: true, isHovering: false) == Islands.selection)
        #expect(RecentLocationsRowView.backgroundColor(isSelected: false, isHovering: true) == Islands.hover)
        #expect(RecentLocationsRowView.backgroundColor(isSelected: false, isHovering: false) == .clear)
    }

    @Test
    func rowHoverStateIsSettable() {
        let view = RecentLocationsRowView(row: row(.pending), isSelected: false, onSelect: {}, onOpen: {})

        view.setHovering(true)
        view.setHovering(false)
    }

    @Test
    func listActionsSelectAndOpenTheRowAtTheirIndex() throws {
        try withTempDir { directory in
            let fixture = try RecentLocationsPopupFixture.make(in: directory, names: ["a.txt", "b.txt", "c.txt"])
            defer { fixture.workspace.close() }
            try fixture.open("c.txt", line: 1)
            fixture.recordBack([fixture.place("a.txt", line: 5), fixture.place("b.txt", line: 10)])
            let model = RecentLocationsViewModel(
                tracker: fixture.tracker,
                workspace: fixture.workspace,
                loadTexts: { urls in Dictionary(uniqueKeysWithValues: urls.map { ($0, "one\ntwo") }) }
            )
            let view = RecentLocationsView(model: model)
            var restoreFlags: [Bool] = []
            model.dismiss = { restoreFlags.append($0) }

            view.selectAction(1)()
            #expect(model.selectedIndex == 1)

            view.openAction(0)()
            #expect(model.selectedIndex == 0)
            #expect(restoreFlags == [false])
            #expect(fixture.selectedName == model.rows.first?.fileName)
        }
    }
}
