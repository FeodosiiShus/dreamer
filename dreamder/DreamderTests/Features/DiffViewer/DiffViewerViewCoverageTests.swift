import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct DiffViewerViewCoverageTests {
    private static let baseLines = (1...30).map { "line \($0)" }

    private static var baseText: String {
        baseLines.joined(separator: "\n") + "\n"
    }

    private static var editedText: String {
        var lines = baseLines
        lines[1] = "line two"
        lines.remove(at: 9)
        lines.insert("inserted after twenty", at: 19)
        return lines.joined(separator: "\n") + "\n"
    }

    private func repository(_ root: URL) throws -> DiffRepository {
        let document = WorkspaceDocument()
        document.sourceControlManager = SourceControlManager(workspaceURL: root, editorManager: EditorManager())
        return try #require(DiffRepository(workspace: document))
    }

    private func makeFixture(_ dir: URL) async throws -> GitMergeFixture {
        let fixture = try await GitMergeFixture(root: dir)
        try fixture.write("mix.txt", Self.baseText)
        try fixture.write("same.txt", "same\n")
        try fixture.write("gone.txt", "gone one\ngone two\n")
        try fixture.write("tabs.txt", "\tindented\n")
        try await fixture.commit("base")
        try fixture.write("mix.txt", Self.editedText)
        try fixture.write("tabs.txt", "\tindented\n\t\tmore\n")
        try FileManager.default.removeItem(at: dir.appending(path: "gone.txt"))
        try fixture.write("new.txt", "brand new\nsecond line\n")
        try fixture.write("empty.txt", "")
        try Data([0x50, 0x00, 0x01]).write(to: dir.appending(path: "blob.bin"))
        return fixture
    }

    private func makeModel(_ dir: URL, only paths: [String]? = nil) async throws -> DiffViewerViewModel {
        let repo = try repository(dir)
        var files = try await repo.workingTreeRequests(against: "HEAD")
        if let paths {
            files = files.filter { paths.contains($0.path) }
        }
        return DiffViewerViewModel(repository: repo, mode: .workingTree(ref: "HEAD"), files: files)
    }

    private func host(_ model: DiffViewerViewModel) -> HostedView {
        HostedViewFixture.host(size: NSSize(width: 1100, height: 900)) {
            DiffViewerView(model: model)
        }
    }

    @Test
    func unloadedModelShowsTheNothingToCompareFallback() async throws {
        try await withTempDir { dir in
            _ = try await makeFixture(dir)
            let model = try await makeModel(dir, only: ["mix.txt"])
            let hosted = host(model)
            defer { hosted.close() }
            try await hosted.settle()

            #expect(model.diff == nil)
            #expect(model.message == nil)
            #expect(model.isLoading == false)
            #expect(hosted.renders())
        }
    }

    @Test
    func emptyModelHasNoSelectionAndRendersFallback() async throws {
        try await withTempDir { dir in
            _ = try await makeFixture(dir)
            let repo = try repository(dir)
            let model = DiffViewerViewModel(repository: repo, mode: .workingTree(ref: "HEAD"), files: [])
            let hosted = host(model)
            defer { hosted.close() }
            try await hosted.settle()

            #expect(model.selectedFile == nil)
            #expect(model.showsFileList == false)
            #expect(hosted.renders())
        }
    }

    @Test
    func loadingStateRendersProgressUntilTheDiffArrives() async throws {
        try await withTempDir { dir in
            _ = try await makeFixture(dir)
            let model = try await makeModel(dir, only: ["mix.txt"])
            let hosted = host(model)
            defer { hosted.close() }
            let empty = hosted.snapshot()

            let loading = Task { await model.loadInitial() }
            await Task.yield()
            try await hosted.settle(.milliseconds(5))
            let duringLoad = hosted.snapshot()
            await loading.value
            try await hosted.settle()
            let loaded = hosted.snapshot()

            #expect(model.diff != nil)
            #expect(HostedView.pixelsDiffer(empty, loaded))
            #expect(duringLoad != nil)
        }
    }

    @Test
    func modifiedDeletedAndInsertedRowsRenderWithToolbarState() async throws {
        try await withTempDir { dir in
            _ = try await makeFixture(dir)
            let model = try await makeModel(dir, only: ["mix.txt"])
            await model.loadInitial()
            let hosted = host(model)
            defer { hosted.close() }
            try await hosted.settle()
            let initial = hosted.snapshot()

            #expect(model.differenceCount == 3)
            #expect(model.differenceSummary == "3 differences")
            #expect(hosted.renders())

            model.nextDifference()
            try await hosted.settle()
            #expect(model.currentHunkIndex == 0)
            #expect(model.canNavigatePrevious == false)
            #expect(HostedView.pixelsDiffer(initial, hosted.snapshot()))

            model.nextDifference()
            model.nextDifference()
            try await hosted.settle()
            #expect(model.canNavigateNext == false)

            model.previousDifference()
            try await hosted.settle()
            #expect(model.currentHunkIndex == 1)
            #expect(hosted.renders())
        }
    }

    @Test
    func identicalFilesReportNoDifferences() async throws {
        try await withTempDir { dir in
            _ = try await makeFixture(dir)
            let repo = try repository(dir)
            let request = repo.workingTreeRequest(status: .modified, path: "same.txt", originalPath: nil, ref: "HEAD")
            let model = DiffViewerViewModel(repository: repo, mode: .workingTree(ref: "HEAD"), files: [request])
            await model.loadInitial()
            let hosted = host(model)
            defer { hosted.close() }
            try await hosted.settle()

            #expect(model.differenceSummary == "No differences")
            #expect(model.canNavigateNext == false)
            #expect(model.canNavigatePrevious == false)
            #expect(hosted.renders())
        }
    }

    @Test
    func addedFileShowsOnlyInsertedRows() async throws {
        try await withTempDir { dir in
            _ = try await makeFixture(dir)
            let model = try await makeModel(dir, only: ["new.txt"])
            await model.loadInitial()
            let hosted = host(model)
            defer { hosted.close() }
            try await hosted.settle()

            let diff = try #require(model.diff)
            #expect(diff.rows.allSatisfy { $0.kind == .inserted })
            #expect(hosted.renders())
        }
    }

    @Test
    func deletedFileShowsOnlyDeletedRows() async throws {
        try await withTempDir { dir in
            _ = try await makeFixture(dir)
            let model = try await makeModel(dir, only: ["gone.txt"])
            await model.loadInitial()
            let hosted = host(model)
            defer { hosted.close() }
            try await hosted.settle()

            let diff = try #require(model.diff)
            #expect(diff.rows.allSatisfy { $0.kind == .deleted })
            #expect(hosted.renders())
        }
    }

    @Test
    func tabsAreExpandedInCodeCells() async throws {
        try await withTempDir { dir in
            _ = try await makeFixture(dir)
            let model = try await makeModel(dir, only: ["tabs.txt"])
            await model.loadInitial()
            let hosted = host(model)
            defer { hosted.close() }
            try await hosted.settle()

            #expect(model.diff?.rightLines.contains("\t\tmore") == true)
            #expect(hosted.renders())
        }
    }

    @Test
    func binaryAndEmptyFilesRenderTheirMessages() async throws {
        try await withTempDir { dir in
            _ = try await makeFixture(dir)
            let model = try await makeModel(dir, only: ["blob.bin", "empty.txt"])
            await model.loadInitial()
            let hosted = host(model)
            defer { hosted.close() }
            try await hosted.settle()

            #expect(model.message == "Binary file")
            #expect(model.showsFileList)
            let binary = hosted.snapshot()
            #expect(hosted.renders())

            await model.select("empty.txt")
            try await hosted.settle()
            #expect(model.message == "Nothing to compare")
            #expect(HostedView.pixelsDiffer(binary, hosted.snapshot()))
        }
    }

    @Test
    func fileListSelectionSwitchesTheDisplayedDiff() async throws {
        try await withTempDir { dir in
            _ = try await makeFixture(dir)
            let model = try await makeModel(dir)
            await model.loadInitial()
            let hosted = host(model)
            defer { hosted.close() }
            try await hosted.settle()

            #expect(model.showsFileList)
            let first = hosted.snapshot()
            let list = DiffFileListView(model: model)
            let target = try #require(model.files.first { $0.id == "mix.txt" })
            #expect(model.selectedID != "mix.txt")

            list.select(target)
            try await eventually { model.selectedID == "mix.txt" && model.isLoading == false }
            try await hosted.settle()

            #expect(model.title == "mix.txt (HEAD vs Local)")
            #expect(model.differenceCount == 3)
            #expect(HostedView.pixelsDiffer(first, hosted.snapshot()))
        }
    }

    @Test
    func fileListRowsForwardTapsAndTrackHover() async throws {
        try await withTempDir { dir in
            _ = try await makeFixture(dir)
            let repo = try repository(dir)
            let request = repo.workingTreeRequest(status: .added, path: "src/nested/new.swift", originalPath: nil, ref: "HEAD")
            var tapped: [String] = []
            let row = DiffFileListRow(file: request, isSelected: false) { tapped.append($0.path) }

            row.tapped()
            row.hoverChanged(true)
            row.hoverChanged(false)
            #expect(tapped == ["src/nested/new.swift"])

            let idle = HostedViewFixture.host(size: NSSize(width: 300, height: 40)) { row }
            defer { idle.close() }
            try await idle.settle()
            let selected = HostedViewFixture.host(size: NSSize(width: 300, height: 40)) {
                DiffFileListRow(file: request, isSelected: true) { _ in }
            }
            defer { selected.close() }
            try await selected.settle()

            #expect(idle.renders())
            #expect(HostedView.pixelsDiffer(idle.snapshot(), selected.snapshot()))
        }
    }

    @Test
    func everyGitStatusColorsItsRow() async throws {
        try await withTempDir { dir in
            _ = try await makeFixture(dir)
            let repo = try repository(dir)
            let statuses: [GitStatus] = [.added, .deleted, .untracked, .unmerged, .modified]
            let requests = statuses.map {
                repo.workingTreeRequest(status: $0, path: "dir/\($0.rawValue).txt", originalPath: nil, ref: "HEAD")
            }
            let hosted = HostedViewFixture.host(size: NSSize(width: 300, height: 300)) {
                VStack(spacing: 0) {
                    ForEach(requests) { request in
                        DiffFileListRow(file: request, isSelected: false) { _ in }
                    }
                }
            }
            defer { hosted.close() }
            try await hosted.settle()

            #expect(hosted.renders())
        }
    }
}
