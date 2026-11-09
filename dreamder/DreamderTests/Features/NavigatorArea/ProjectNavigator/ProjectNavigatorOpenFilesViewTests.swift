import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ProjectNavigatorOpenFilesViewTests {
    private func makeFiles(in dir: URL) throws -> [CEWorkspaceFile] {
        try FileManager.default.createDirectory(at: dir.appending(path: "sub/deeper"), withIntermediateDirectories: true)
        let urls = [
            dir.appending(path: "a.swift"),
            dir.appending(path: "sub/b.txt"),
            dir.appending(path: "sub/deeper/c.md")
        ]
        for url in urls {
            try "content\n".write(to: url, atomically: true, encoding: .utf8)
        }
        return urls.map { CEWorkspaceFile(url: $0) }
    }

    @Test
    func modelFollowsOpenTabsOfTheActiveEditor() async throws {
        try await withTempDir { dir in
            let files = try makeFiles(in: dir)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let manager = try #require(workspace.editorManager)
            let model = ProjectNavigatorOpenFilesModel()

            model.attach(manager)
            #expect(model.files.isEmpty)
            #expect(model.selectedFileID == nil)

            manager.openTab(item: files[0])
            try await eventually { model.files.map(\.id) == [files[0].id] && model.selectedFileID == files[0].id }

            manager.openTab(item: files[1])
            try await eventually {
                model.files.map(\.id) == [files[0].id, files[1].id] && model.selectedFileID == files[1].id
            }

            manager.activeEditor.setSelectedTab(files[0])
            try await eventually { model.selectedFileID == files[0].id }
            #expect(model.files.map(\.id) == [files[0].id, files[1].id])

            manager.activeEditor.closeTab(file: files[1])
            try await eventually { model.files.map(\.id) == [files[0].id] }
        }
    }

    @Test
    func attachingTheSameManagerAgainRebuildsAndANewManagerReplacesTheObservation() async throws {
        try await withTempDir { dir in
            let files = try makeFiles(in: dir)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let manager = try #require(workspace.editorManager)
            let model = ProjectNavigatorOpenFilesModel()
            model.attach(manager)

            manager.openTab(item: files[0])
            try await eventually { model.files.count == 1 }
            model.attach(manager)
            #expect(model.files.map(\.id) == [files[0].id])
            #expect(model.selectedFileID == files[0].id)

            let other = EditorManager()
            other.openTab(item: files[2])
            model.attach(other)
            #expect(model.files.map(\.id) == [files[2].id])
            #expect(model.selectedFileID == files[2].id)

            other.openTab(item: files[1])
            try await eventually { model.files.map(\.id) == [files[2].id, files[1].id] }

            manager.openTab(item: files[1])
            try await Task.sleep(for: .milliseconds(100))
            #expect(model.files.map(\.id) == [files[2].id, files[1].id])
        }
    }

    @Test
    func modelCollectsFilesOfEverySplitOnceAndPutsTheActiveEditorFirst() async throws {
        try await withTempDir { dir in
            let files = try makeFiles(in: dir)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let manager = try #require(workspace.editorManager)
            let first = manager.activeEditor
            manager.openTab(item: files[0])
            manager.openTab(item: files[1])

            let model = ProjectNavigatorOpenFilesModel()
            model.attach(manager)
            #expect(model.files.map(\.id) == [files[0].id, files[1].id])

            let right = try #require(manager.splitActiveEditor(.trailing, workspace: workspace))
            manager.openTab(item: files[2], in: right)
            let below = try #require(manager.splitActiveEditor(.bottom, workspace: workspace))
            try await eventually { model.files.count == 3 }
            #expect(manager.activeEditor === below)
            #expect(model.files.map(\.id).first == below.selectedTab?.file.id)
            #expect(Set(model.files.map(\.id)) == Set(files.map(\.id)))

            manager.activeEditor = first
            try await eventually { model.selectedFileID == first.selectedTab?.file.id && model.files.count == 3 }
            #expect(model.files.map(\.id).first == first.tabs.first?.file.id)
        }
    }

    @Test
    func openActionOpensTheFileInTheActiveEditor() async throws {
        try withTempDir { dir in
            let files = try makeFiles(in: dir)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let manager = try #require(workspace.editorManager)

            ProjectNavigatorOpenFilesView.openAction(for: files[1], in: manager)()
            #expect(manager.activeEditor.selectedTab?.file == files[1])
            #expect(manager.activeEditor.tabs.count == 1)
        }
    }

    @Test
    func viewShowsPlaceholderThenOneRowPerOpenFile() async throws {
        try await withTempDir { dir in
            let files = try makeFiles(in: dir)
            let outside = try makeTemporaryDirectory(label: "OpenFilesOutside")
            defer { removeTemporaryDirectory(outside) }
            let outsideURL = outside.appending(path: "elsewhere.json")
            try "{}".write(to: outsideURL, atomically: true, encoding: .utf8)
            let outsideFile = CEWorkspaceFile(url: outsideURL)

            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let manager = try #require(workspace.editorManager)

            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { ProjectNavigatorOpenFilesView() }
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())
            let empty = hosted.snapshot()

            manager.openTab(item: files[0])
            try await hosted.settle()
            let one = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(empty, one))

            manager.openTab(item: files[1])
            manager.openTab(item: files[2])
            manager.openTab(item: outsideFile)
            try await hosted.settle()
            let many = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(one, many))

            manager.activeEditor.setSelectedTab(files[0])
            try await hosted.settle()
            #expect(HostedView.pixelsDiffer(many, hosted.snapshot()))
        }
    }

    @Test
    func viewReattachesWhenTheActiveEditorChanges() async throws {
        try await withTempDir { dir in
            let files = try makeFiles(in: dir)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let manager = try #require(workspace.editorManager)
            manager.openTab(item: files[0])

            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { ProjectNavigatorOpenFilesView() }
            defer { hosted.close() }
            try await hosted.settle()
            let before = hosted.snapshot()

            let split = try #require(manager.splitActiveEditor(.trailing, workspace: workspace))
            manager.openTab(item: files[1], in: split)
            try await hosted.settle()
            #expect(manager.activeEditor === split)
            #expect(HostedView.pixelsDiffer(before, hosted.snapshot()))
        }
    }
}
