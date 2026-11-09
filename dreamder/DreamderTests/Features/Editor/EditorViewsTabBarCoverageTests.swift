import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class EditorViewsSelectorRecorder {
    var selectors: [Selector] = []

    func record(_ selector: Selector) {
        selectors.append(selector)
    }
}

@MainActor
private final class EditorLayoutProbe {
    var subLayout: EditorLayoutView.SubEditorLayoutView<EditorLayoutProbePane>?
    var tokens: [Editor.ID: UUID] = [:]
    var appeared: [Editor.ID] = []
    var disappeared: [Editor.ID] = []

    func record(_ layout: EditorLayout, token: UUID) {
        if case .one(let editor) = layout {
            tokens[editor.id] = token
        }
    }

    func appear(_ layout: EditorLayout) {
        if case .one(let editor) = layout {
            appeared.append(editor.id)
        }
    }

    func disappear(_ layout: EditorLayout) {
        if case .one(let editor) = layout {
            disappeared.append(editor.id)
        }
    }
}

private struct EditorLayoutProbePane: View {
    let layout: EditorLayout
    let probe: EditorLayoutProbe
    @State private var token = UUID()

    var body: some View {
        recordedPane()
    }

    private func recordedPane() -> some View {
        probe.record(layout, token: token)
        return Color.clear
            .onAppear { probe.appear(layout) }
            .onDisappear { probe.disappear(layout) }
    }
}

private struct EditorLayoutProbeView: View {
    let data: SplitViewData
    let probe: EditorLayoutProbe

    var body: some View {
        let subLayout = EditorLayoutView.SubEditorLayoutView(data: data) { layout in
            EditorLayoutProbePane(layout: layout, probe: probe)
        }
        subLayout.onAppear {
            probe.subLayout = subLayout
        }
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct EditorEmptyStateTabBarCoverageTests {
    @Test
    func hintsSendTheirResponderChainActions() {
        let recorder = EditorViewsSelectorRecorder()
        let view = EditorEmptyStateView(sendAction: { recorder.record($0) })

        view.openSearchEverywhere()
        view.openQuickly()

        #expect(recorder.selectors == [
            #selector(DreamderWindowController.openSearchEverywhere(_:)),
            #selector(DreamderWindowController.openQuickly(_:))
        ])
    }

    @Test
    func emptyStateRendersItsHints() async throws {
        let recorder = IdealSizeRecorder()
        let hosted = HostedViewFixture.host(size: NSSize(width: 500, height: 300)) {
            EditorEmptyStateView(sendAction: { _ in })
                .recordingIdealSize(in: recorder)
        }
        defer { hosted.close() }
        let ideal = try await hosted.idealSize(of: recorder)

        #expect(hosted.renders())
        #expect(ideal.width >= 280)
        #expect(ideal.height > 0)
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct EditorLayoutViewTabBarCoverageTests {
    private func makeEditors(_ count: Int) -> [Editor] {
        (0..<count).map { _ in Editor() }
    }

    private struct HostedProbe {
        let hosted: HostedView
        let subLayout: EditorLayoutView.SubEditorLayoutView<EditorLayoutProbePane>
        let probe: EditorLayoutProbe
    }

    private func hostProbe(
        for data: SplitViewData
    ) async throws -> HostedProbe {
        let probe = EditorLayoutProbe()
        let hosted = HostedViewFixture.host(size: NSSize(width: 200, height: 100)) {
            EditorLayoutProbeView(data: data, probe: probe)
        }
        try await eventually(timeout: .seconds(5)) {
            hosted.layout()
            return probe.subLayout != nil
        }
        let subLayout = try #require(probe.subLayout)
        return HostedProbe(hosted: hosted, subLayout: subLayout, probe: probe)
    }

    @Test
    func verticalSplitMarksOnlyTheOuterEditorsAsTouchingTheToolbarEdges() async throws {
        let editors = makeEditors(3)
        let data = SplitViewData(.vertical, editorLayouts: editors.map { .one($0) })
        let hostedProbe = try await hostProbe(for: data)
        let hosted = hostedProbe.hosted
        let subLayout = hostedProbe.subLayout
        defer { hosted.close() }

        var first = VerticalEdge.Set.all
        subLayout.calcIsAtEdge(current: &first, index: 0)
        var middle = VerticalEdge.Set.all
        subLayout.calcIsAtEdge(current: &middle, index: 1)
        var last = VerticalEdge.Set.all
        subLayout.calcIsAtEdge(current: &last, index: 2)

        #expect(first == [.top])
        #expect(middle == [])
        #expect(last == [.bottom])
    }

    @Test
    func singleEditorAndHorizontalSplitsKeepEveryEdge() async throws {
        let single = SplitViewData(.vertical, editorLayouts: makeEditors(1).map { .one($0) })
        let horizontal = SplitViewData(.horizontal, editorLayouts: makeEditors(2).map { .one($0) })
        let singleProbe = try await hostProbe(for: single)
        let singleHosted = singleProbe.hosted
        let singleLayout = singleProbe.subLayout
        defer { singleHosted.close() }
        let horizontalProbe = try await hostProbe(for: horizontal)
        let horizontalHosted = horizontalProbe.hosted
        let horizontalLayout = horizontalProbe.subLayout
        defer { horizontalHosted.close() }

        var singleEdges = VerticalEdge.Set.all
        singleLayout.calcIsAtEdge(current: &singleEdges, index: 0)
        var horizontalEdges = VerticalEdge.Set.all
        horizontalLayout.calcIsAtEdge(current: &horizontalEdges, index: 1)

        #expect(singleEdges == .all)
        #expect(horizontalEdges == .all)
    }

    @Test
    func splitActionInsertsTheNewEditorNextToTheSourceEditor() async throws {
        let editors = makeEditors(2)
        let data = SplitViewData(.vertical, editorLayouts: editors.map { .one($0) })
        let hostedProbe = try await hostProbe(for: data)
        let hosted = hostedProbe.hosted
        let subLayout = hostedProbe.subLayout
        defer { hosted.close() }
        let newEditor = Editor()

        subLayout.splitAction(at: 0)(.bottom, newEditor)

        #expect(data.editorLayouts.count == 3)
        #expect(data.getFlattened().map(\.id) == [editors[0].id, newEditor.id, editors[1].id])
        #expect(newEditor.parent === data)
    }

    @Test
    func closingTheFirstOfThreeSplitsKeepsTheRemainingPanesStateWithTheirEditors() async throws {
        let editors = makeEditors(3)
        let data = SplitViewData(.horizontal, editorLayouts: editors.map { .one($0) })
        let hostedProbe = try await hostProbe(for: data)
        let hosted = hostedProbe.hosted
        let probe = hostedProbe.probe
        defer { hosted.close() }
        try await eventually(timeout: .seconds(5)) {
            hosted.layout()
            return probe.tokens.count == 3
        }
        let tokensBefore = probe.tokens

        data.closeEditor(with: editors[0].id)

        try await eventually(timeout: .seconds(5)) {
            hosted.layout()
            return !probe.disappeared.isEmpty
        }
        #expect(probe.disappeared == [editors[0].id])
        #expect(probe.appeared.count == 3)
        #expect(probe.tokens[editors[1].id] == tokensBefore[editors[1].id])
        #expect(probe.tokens[editors[2].id] == tokensBefore[editors[2].id])
    }

    @Test
    func layoutIdentityFollowsTheEditorOrTheSplitContainer() {
        let editor = Editor()
        let other = Editor()
        let nested = SplitViewData(.vertical, editorLayouts: [.one(other)])

        #expect(EditorLayout.one(editor).id == .editor(editor.id))
        #expect(EditorLayout.one(editor).id != EditorLayout.one(other).id)
        #expect(EditorLayout.vertical(nested).id == .split(ObjectIdentifier(nested)))
        #expect(EditorLayout.horizontal(nested).id == EditorLayout.vertical(nested).id)
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct InspectionWidgetTabBarCoverageTests {
    private func diagnostic(_ url: URL, _ severity: WorkspaceDiagnostic.Severity) -> WorkspaceDiagnostic {
        WorkspaceDiagnostic(
            fileURL: url,
            startLine: 1,
            startColumn: 1,
            endLine: 1,
            endColumn: 2,
            severity: severity,
            message: "message \(severity.rawValue)",
            source: nil,
            code: nil
        )
    }

    private func size(of content: InspectionWidgetContent) async throws -> CGSize {
        let recorder = IdealSizeRecorder()
        let hosted = HostedViewFixture.host(size: NSSize(width: 300, height: 60)) {
            content.recordingIdealSize(in: recorder, floor: 1)
        }
        defer { hosted.close() }
        return try await hosted.idealSize(of: recorder)
    }

    @Test
    func chipReflectsErrorsWarningsAndTheHealthyState() async throws {
        try await withTempDir { directory in
            let url = directory.appending(path: "Sample.md")
            let document = try TabBarCoverageLanguageServer.makeDocument(
                at: url,
                contents: "# Sample\n",
                typeIdentifier: "public.source-code"
            )
            let store = DiagnosticsStore()
            let service = LSPService()
            let manager = ToolWindowManager()
            @MainActor func content(_ fileURL: URL?, service: LSPService) -> InspectionWidgetContent {
                InspectionWidgetContent(fileURL: fileURL, store: store, lspService: service, toolWindowManager: manager)
            }

            let hidden = try await size(of: content(url, service: service))
            let withoutFile = try await size(of: content(nil, service: service))
            #expect(withoutFile == hidden)

            store.replace([diagnostic(url, .information)], for: url)
            #expect(try await size(of: content(url, service: service)) == hidden)

            store.replace([diagnostic(url, .error)], for: url)
            let errors = try await size(of: content(url, service: service))
            store.replace([diagnostic(url, .warning)], for: url)
            let warnings = try await size(of: content(url, service: service))
            store.replace([diagnostic(url, .error), diagnostic(url, .warning)], for: url)
            let both = try await size(of: content(url, service: service))
            #expect(errors.width > hidden.width)
            #expect(errors.height == 24)
            #expect(warnings.width > hidden.width)
            #expect(both.width > errors.width)
            #expect(both.width > warnings.width)

            store.clear(url)
            try await TabBarCoverageLanguageServer.install(
                symbolPayload: TabBarCoverageLanguageServer.nullSymbols,
                tracking: document,
                in: service
            )
            let healthy = try await size(of: content(url, service: service))
            #expect(healthy.width > hidden.width)
            #expect(healthy.height == 24)
            #expect(try await size(of: content(nil, service: service)) == hidden)
        }
    }

    @Test
    func tappingTheChipShowsTheProblemsToolWindow() {
        let manager = ToolWindowManager()
        let content = InspectionWidgetContent(
            fileURL: nil,
            store: DiagnosticsStore(),
            lspService: LSPService(),
            toolWindowManager: manager
        )
        #expect(manager.isVisible(.problems) == false)

        content.showProblems()

        #expect(manager.isVisible(.problems))
    }

    @Test
    func hoverStateIsSettable() {
        let content = InspectionWidgetContent(
            fileURL: nil,
            store: DiagnosticsStore(),
            lspService: LSPService(),
            toolWindowManager: ToolWindowManager()
        )

        content.setHovering(true)
        content.setHovering(false)
    }

    @Test
    func widgetFollowsTheWorkspaceDiagnosticsOfTheSelectedTab() async throws {
        try await withTempDir { directory in
            try "plain\n".write(to: directory.appending(path: "Plain.txt"), atomically: true, encoding: .utf8)
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let manager = try #require(workspace.editorManager)
            let editor = manager.activeEditor
            let url = directory.appending(path: "Plain.txt")
            let recorder = IdealSizeRecorder()
            let hosted = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 300, height: 60)) {
                InspectionWidget(editor: editor)
                    .recordingIdealSize(in: recorder, floor: 1)
            }
            defer { hosted.close() }
            let withoutTab = try await hosted.idealSize(of: recorder)
            #expect(withoutTab == CGSize(width: 1, height: 1))

            let file = try #require(workspace.workspaceFileManager?.getFile(
                url.path(percentEncoded: false),
                createIfNotFound: true
            ))
            manager.openTab(item: file)
            workspace.diagnosticsStore.replace([diagnostic(url, .error)], for: url)

            try await eventually(timeout: .seconds(30)) {
                hosted.layout()
                return (recorder.size?.width ?? 0) > withoutTab.width
            }
            #expect(recorder.size?.height == 24)

            workspace.diagnosticsStore.clearAll()
            try await eventually(timeout: .seconds(30)) {
                hosted.layout()
                return recorder.size == withoutTab
            }
        }
    }
}
