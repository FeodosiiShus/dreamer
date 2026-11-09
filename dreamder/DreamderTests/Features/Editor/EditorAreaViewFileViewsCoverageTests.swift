import AppKit
import CodeEditTextView
import Foundation
import QuickLookUI
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import Dreamder

@MainActor
private struct EditorAreaHarness: View {
    let editor: Editor
    @FocusState private var focus: Editor?

    var body: some View {
        EditorAreaView(editor: editor, focus: $focus)
    }
}

@MainActor
@Suite(.uiGate)
struct EditorAreaViewFileViewsCoverageTests {
    private struct Setup {
        let workspace: WorkspaceDocument
        let manager: EditorManager
        let editor: Editor
    }

    private func makeSetup(in directory: URL) throws -> Setup {
        let workspace = try HostedViewFixture.makeWorkspace(in: directory)
        let manager = try #require(workspace.editorManager)
        let editor = manager.activeEditor
        editor.workspace = workspace
        return Setup(workspace: workspace, manager: manager, editor: editor)
    }

    private func host(_ setup: Setup) throws -> HostedView {
        let editor = setup.editor
        return try HostedViewFixture.hostInWorkspace(setup.workspace) {
            EditorAreaHarness(editor: editor)
        }
    }

    private func nonTextFile(
        at url: URL,
        type: String = FileViewsCoverageFixtures.pngType
    ) throws -> (file: CEWorkspaceFile, document: CodeFileDocument) {
        let file = CEWorkspaceFile(url: url)
        let document = try FileViewsCoverageFixtures.nonTextDocument(at: url, type: type)
        file.fileDocument = document
        return (file, document)
    }

    private func textFile(at url: URL, contents: String) throws -> (file: CEWorkspaceFile, document: CodeFileDocument) {
        let file = CEWorkspaceFile(url: url)
        let document = try FileViewsCoverageFixtures.textDocument(at: url, contents: contents)
        file.fileDocument = document
        return (file, document)
    }

    @Test
    func emptyEditorHostsTheEmptyStateAndBecomesActiveOnTap() async throws {
        try await withTempDir { directory in
            let setup = try makeSetup(in: directory)
            let sibling = try #require(setup.manager.splitActiveEditor(.trailing, workspace: setup.workspace))
            setup.manager.activeEditor = sibling
            #expect(setup.manager.activeEditor !== setup.editor)

            let hosted = try host(setup)
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.views(of: QLPreviewView.self).isEmpty)

            EditorAreaView.activate(setup.editor, in: setup.manager)
            #expect(setup.manager.activeEditor === setup.editor)
        }
    }

    @Test
    func imageTabShowsPreviewAndSwitchingToATextTabReplacesIt() async throws {
        try await withTempDir { directory in
            let setup = try makeSetup(in: directory)
            let png = directory.appending(path: "picture.png")
            try FileViewsCoverageFixtures.writePNG(to: png)
            let image = try nonTextFile(at: png)
            let text = try textFile(at: directory.appending(path: "note.txt"), contents: "hello\n")
            setup.editor.openTab(file: image.file)

            let hosted = try host(setup)
            defer { hosted.close() }
            try await eventually { hosted.views(of: QLPreviewView.self).count == 1 }

            setup.editor.openTab(file: text.file)
            try await eventually { !hosted.views(of: TextView.self).isEmpty }
            #expect(hosted.views(of: QLPreviewView.self).isEmpty)

            withExtendedLifetime((image.document, text.document)) {}
        }
    }

    @Test
    func tabWithoutDocumentShowsLoadingUntilTheDocumentArrivesAndAgainWhenItGoes() async throws {
        try await withTempDir { directory in
            let setup = try makeSetup(in: directory)
            setup.editor.workspace = nil
            let png = directory.appending(path: "picture.png")
            try FileViewsCoverageFixtures.writePNG(to: png)
            let file = CEWorkspaceFile(url: png)
            setup.editor.openTab(file: file)
            #expect(file.fileDocument == nil)

            let hosted = try host(setup)
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.views(of: QLPreviewView.self).isEmpty)

            let document = try FileViewsCoverageFixtures.nonTextDocument(
                at: png,
                type: FileViewsCoverageFixtures.pngType
            )
            file.fileDocument = document
            try await eventually(timeout: .seconds(30)) { hosted.views(of: QLPreviewView.self).count == 1 }

            file.fileDocument = nil
            try await eventually(timeout: .seconds(30)) { hosted.views(of: QLPreviewView.self).isEmpty }
            withExtendedLifetime(document) {}
        }
    }

    @Test
    func droppingAFileURLOpensItInTheEditorAndActivatesIt() async throws {
        try await withTempDir { directory in
            let setup = try makeSetup(in: directory)
            let sibling = try #require(setup.manager.splitActiveEditor(.trailing, workspace: setup.workspace))
            #expect(setup.manager.activeEditor === sibling)
            let dropped = directory.appending(path: "dropped.txt")
            try "dropped".write(to: dropped, atomically: true, encoding: .utf8)

            let provider = NSItemProvider()
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.fileURL.identifier,
                visibility: .all
            ) { completion in
                completion(dropped.dataRepresentation, nil)
                return nil
            }
            let handler = EditorAreaView.makeDropHandler(editor: setup.editor, editorManager: setup.manager)

            #expect(handler([provider, NSItemProvider()]))

            try await eventually(timeout: .seconds(10)) {
                setup.editor.tabs.contains { $0.file.url.path == dropped.path }
            }
            #expect(setup.manager.activeEditor === setup.editor)
        }
    }

    @Test
    func tabBarVisibilityFollowsNavigationStyleAndEditorTabs() throws {
        let empty = Editor()
        let plain = Editor()
        plain.openTab(file: CEWorkspaceFile(url: URL(filePath: "/fake/dir/a.txt")))
        let temporaryOnly = Editor()
        temporaryOnly.openTab(file: CEWorkspaceFile(url: URL(filePath: "/fake/dir/b.txt")))
        temporaryOnly.temporaryTab = temporaryOnly.tabs[0]
        let temporaryWithOthers = Editor()
        temporaryWithOthers.openTab(file: CEWorkspaceFile(url: URL(filePath: "/fake/dir/c.txt")))
        temporaryWithOthers.openTab(file: CEWorkspaceFile(url: URL(filePath: "/fake/dir/d.txt")))
        temporaryWithOthers.temporaryTab = temporaryWithOthers.tabs[0]

        #expect(EditorAreaView.showsTabBar(style: .openInTabs, editors: []))
        #expect(!EditorAreaView.showsTabBar(style: .openInPlace, editors: [empty]))
        #expect(EditorAreaView.showsTabBar(style: .openInPlace, editors: [empty, plain]))
        #expect(!EditorAreaView.showsTabBar(style: .openInPlace, editors: [temporaryOnly]))
        #expect(EditorAreaView.showsTabBar(style: .openInPlace, editors: [temporaryWithOthers]))
    }

    @Test
    func switchingToOpenInPlaceAdoptsTheSingleTabAsTemporary() {
        let single = Editor()
        single.openTab(file: CEWorkspaceFile(url: URL(filePath: "/fake/dir/a.txt")))
        let pair = Editor()
        pair.openTab(file: CEWorkspaceFile(url: URL(filePath: "/fake/dir/b.txt")))
        pair.openTab(file: CEWorkspaceFile(url: URL(filePath: "/fake/dir/c.txt")))
        let tabsStyle = Editor()
        tabsStyle.openTab(file: CEWorkspaceFile(url: URL(filePath: "/fake/dir/d.txt")))

        EditorAreaView.adoptTemporaryTab(in: single, for: .openInPlace)
        EditorAreaView.adoptTemporaryTab(in: pair, for: .openInPlace)
        EditorAreaView.adoptTemporaryTab(in: tabsStyle, for: .openInTabs)

        #expect(single.temporaryTab == single.tabs[0])
        #expect(pair.temporaryTab == nil)
        #expect(tabsStyle.temporaryTab == nil)
    }

    @Test
    func tapAndNavigationStyleActionsActOnTheEditor() throws {
        try withTempDir { directory in
            let setup = try makeSetup(in: directory)
            let sibling = try #require(setup.manager.splitActiveEditor(.trailing, workspace: setup.workspace))
            #expect(setup.manager.activeEditor === sibling)

            EditorAreaView.activateAction(setup.editor, in: setup.manager)()
            #expect(setup.manager.activeEditor === setup.editor)

            let single = Editor()
            single.openTab(file: CEWorkspaceFile(url: URL(filePath: "/fake/dir/a.txt")))
            EditorAreaView.adoptTemporaryTabAction(in: single)(.openInTabs, .openInPlace)
            #expect(single.temporaryTab != nil)
            #expect(single.temporaryTab == single.tabs.first)
        }
    }

    @Test
    func loaderHelpersFallBackOnlyWhenNoDocumentIsGiven() {
        let document = CodeFileDocument()
        let current: EditorAreaView.DocumentLoader = { nil }

        #expect(EditorAreaView.loaderOrEmpty(for: document)() === document)
        #expect(EditorAreaView.loaderOrEmpty(for: nil)() == nil)
        #expect(EditorAreaView.keepingCurrent(current, unless: document)?() === document)
        #expect(EditorAreaView.keepingCurrent(current, unless: nil)?() == nil)
        #expect(EditorAreaView.keepingCurrent(nil, unless: nil) == nil)
    }

    @Test
    func inactiveEditorsDimOnlyWhenTheSettingIsOn() {
        #expect(EditorAreaView.opacity(dimsWithoutFocus: false, isActive: false) == 1)
        #expect(EditorAreaView.opacity(dimsWithoutFocus: true, isActive: true) == 1)
        #expect(EditorAreaView.opacity(dimsWithoutFocus: true, isActive: false) == 0.5)
    }

    @Test
    func loaderResolvesTheDocumentOnlyWhileOneIsGiven() {
        let document = CodeFileDocument()

        let loader = EditorAreaView.loader(for: document)

        #expect(loader?() === document)
        #expect(EditorAreaView.loader(for: nil) == nil)
        #expect(EditorAreaView.noDocument() == nil)
    }

    @Test
    func loadedDocumentIdentifiesTheSelectedFileAndItsDocument() throws {
        try withTempDir { directory in
            let url = directory.appending(path: "note.txt")
            let loaded = try textFile(at: url, contents: "hello\n")
            let tab = EditorInstance(workspace: nil, file: loaded.file)

            let identity = try #require(EditorAreaView.loadedDocument(of: tab))

            #expect(identity.fileID == loaded.file.id)
            #expect(identity.document == ObjectIdentifier(loaded.document))
            #expect(EditorAreaView.loadedDocument(of: nil) == nil)
            loaded.file.fileDocument = nil
            #expect(EditorAreaView.loadedDocument(of: tab)?.document == nil)
        }
    }

    @Test
    func aLoaderIsReplacedOnlyWhenTheSameFileChangesItsDocument() throws {
        try withTempDir { directory in
            let loaded = try textFile(at: directory.appending(path: "note.txt"), contents: "hello\n")
            let other = CEWorkspaceFile(url: directory.appending(path: "other.txt"))
            let tab = EditorInstance(workspace: nil, file: loaded.file)
            let before = EditorAreaView.LoadedDocument(fileID: loaded.file.id, document: nil)
            let after = try #require(EditorAreaView.loadedDocument(of: tab))
            let elsewhere = EditorAreaView.LoadedDocument(fileID: other.id, document: nil)

            let replaced = EditorAreaView.loader(afterLoadedDocumentChangedFrom: before, to: after, in: tab)

            #expect(replaced?() === loaded.document)
            #expect(EditorAreaView.loader(afterLoadedDocumentChangedFrom: elsewhere, to: after, in: tab) == nil)
            #expect(EditorAreaView.loader(afterLoadedDocumentChangedFrom: nil, to: after, in: tab) == nil)
            #expect(EditorAreaView.loader(afterLoadedDocumentChangedFrom: before, to: nil, in: tab) == nil)
            loaded.file.fileDocument = nil
            let emptied = EditorAreaView.loader(afterLoadedDocumentChangedFrom: after, to: before, in: tab)
            #expect(emptied?() == nil)
        }
    }
}
