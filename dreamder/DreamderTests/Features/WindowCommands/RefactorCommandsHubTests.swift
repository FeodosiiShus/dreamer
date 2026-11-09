import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct EditorFeatureHubTests {
    private func instance(_ name: String) -> EditorInstance {
        EditorInstance(workspace: nil, file: CEWorkspaceFile(url: URL(filePath: "/fake/\(name)")))
    }

    private func openTab(_ name: String, in workspace: WorkspaceDocument, dir: URL) throws {
        try "alpha beta\n".write(to: dir.appending(path: name), atomically: true, encoding: .utf8)
        let file = try #require(workspace.workspaceFileManager?.getFile(
            dir.appending(path: name).path(percentEncoded: false),
            createIfNotFound: true
        ))
        workspace.editorManager?.openTab(item: file)
    }

    @Test
    func aTabAlwaysGetsTheSameHub() {
        let first = instance("a.txt")
        let second = instance("b.txt")

        let hub = EditorFeatureHubs.hub(for: first)

        #expect(EditorFeatureHubs.hub(for: first) === hub)
        #expect(EditorFeatureHubs.hub(for: second) !== hub)
    }

    @Test
    func activeHubIsNilWithoutAWorkspaceOrASelectedTab() throws {
        #expect(EditorFeatureHubs.activeHub(in: nil) == nil)
        try withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }

            #expect(EditorFeatureHubs.activeHub(in: workspace) == nil)
        }
    }

    @Test
    func activeHubBelongsToTheSelectedTab() throws {
        try withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            try openTab("a.txt", in: workspace, dir: dir)
            let tab = try #require(workspace.editorManager?.activeEditor.selectedTab)

            #expect(EditorFeatureHubs.activeHub(in: workspace) === EditorFeatureHubs.hub(for: tab))
        }
    }

    @Test
    func caretGeometryNeedsAWindowAndALaidOutCaret() async throws {
        #expect(EditorCaretGeometry.screenRect(ofOffset: 0, in: TextView(string: "alpha")) == nil)

        try await withTempDir { dir in
            let fixture = try HostedSourceEditorFixture.make(in: dir, contents: "alpha beta\n")
            let hosted = fixture.host(coordinators: [fixture.document.contentCoordinator])
            defer { hosted.close() }
            try await eventually { hosted.controller?.textView?.window === hosted.window }
            let textView = try #require(hosted.controller?.textView)

            try await eventually { EditorCaretGeometry.screenRect(ofOffset: 0, in: textView) != nil }
            let rect = try #require(EditorCaretGeometry.screenRect(ofOffset: 0, in: textView))

            #expect(rect.height > 0)
        }
    }

    @MainActor
    private struct ActiveEditor {
        let workspace: WorkspaceDocument
        let hosted: HostedSourceEditor
        let textView: TextView

        func close() {
            hosted.close()
            workspace.close()
        }
    }

    private func makeActiveEditor(
        in dir: URL,
        contents: String,
        coordinators: (HostedSourceEditorFixture) -> [TextViewCoordinator]
    ) async throws -> ActiveEditor {
        let workspace = try HostedViewFixture.makeWorkspace(in: dir)
        let fixture = try HostedSourceEditorFixture.make(in: dir, contents: contents)
        fixture.editorInstance.file.fileDocument = fixture.document
        let editor = try #require(workspace.editorManager?.activeEditor)
        editor.tabs.append(fixture.editorInstance)
        editor.setSelectedTab(fixture.editorInstance.file)
        let hosted = fixture.host(
            coordinators: [fixture.document.contentCoordinator] + coordinators(fixture),
            size: NSSize(width: 900, height: 600)
        )
        try await eventually { hosted.controller?.textView?.window === hosted.window }
        let textView = try #require(hosted.controller?.textView)
        return ActiveEditor(workspace: workspace, hosted: hosted, textView: textView)
    }

    @Test
    func selectionCommandsReachTheActiveTabsCoordinator() async throws {
        try await withTempDir { dir in
            let active = try await makeActiveEditor(in: dir, contents: "alpha beta\n") { fixture in
                [SelectionRangeCoordinator(
                    editorInstance: fixture.editorInstance,
                    codeFile: fixture.document,
                    clientProvider: { nil }
                )]
            }
            defer { active.close() }
            active.textView.selectionManager.setSelectedRanges([NSRange(location: 7, length: 0)])

            await EditorFeatureCommands.expandSelection(workspace: active.workspace)
            #expect(active.textView.selectionManager.textSelections.map(\.range) == [NSRange(location: 6, length: 4)])

            EditorFeatureCommands.shrinkSelection(workspace: active.workspace)
            #expect(active.textView.selectionManager.textSelections.map(\.range) == [NSRange(location: 7, length: 0)])
        }
    }

    @Test
    func foldingCommandsReachTheActiveTabsCoordinator() async throws {
        try await withTempDir { dir in
            var folding: FoldingCoordinator?
            let active = try await makeActiveEditor(
                in: dir,
                contents: "func a() {\n    let x = 1\n    let y = 2\n}\n"
            ) { fixture in
                let coordinator = FoldingCoordinator(
                    editorInstance: fixture.editorInstance,
                    codeFile: fixture.document,
                    clientProvider: { nil }
                )
                folding = coordinator
                return [coordinator]
            }
            defer { active.close() }
            let coordinator = try #require(folding)
            active.textView.selectionManager.setSelectedRanges([NSRange(location: 0, length: 0)])

            await EditorFeatureCommands.collapseCodeBlock(workspace: active.workspace)
            #expect(coordinator.collapsedRegions.count == 1)

            EditorFeatureCommands.expandCodeBlock(workspace: active.workspace)
            #expect(coordinator.collapsedRegions.isEmpty)

            await EditorFeatureCommands.collapseAll(workspace: active.workspace)
            #expect(coordinator.collapsedRegions.count == 1)

            EditorFeatureCommands.expandAll(workspace: active.workspace)
            #expect(coordinator.collapsedRegions.isEmpty)

            await EditorFeatureCommands.collapseComments(workspace: active.workspace)
            #expect(coordinator.collapsedRegions.isEmpty)
        }
    }

    @Test
    func parameterInfoCommandReachesTheActiveTabsCoordinator() async throws {
        try await withTempDir { dir in
            let counter = ClientLookupCounter()
            let active = try await makeActiveEditor(in: dir, contents: "call(1, 2)\n") { fixture in
                [SignatureHelpCoordinator(
                    editorInstance: fixture.editorInstance,
                    codeFile: fixture.document,
                    clientProvider: {
                        counter.lookups += 1
                        return nil
                    }
                )]
            }
            defer { active.close() }
            active.textView.selectionManager.setSelectedRanges([NSRange(location: 5, length: 0)])

            await EditorFeatureCommands.showParameterInfo(workspace: active.workspace)

            #expect(counter.lookups > 0)
        }
    }
}

@MainActor
private final class ClientLookupCounter {
    var lookups = 0
}
