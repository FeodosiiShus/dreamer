import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct IslandsWorkspaceView: View {
    @Environment(\.window.value)
    private var window: NSWindow?

    @Environment(\.colorScheme)
    private var colorScheme

    @Environment(WorkspaceDocument.self) private var workspace
    @Environment(EditorManager.self) private var editorManager
    @Environment(UtilityAreaViewModel.self) private var utilityAreaViewModel
    @Environment(TaskManager.self) private var taskManager
    @Environment(ToolWindowManager.self) private var toolWindowManager

    @AppSettings(\.theme.matchAppearance)
    private var matchAppearance

    @AppSettings(\.sourceControl.general.sourceControlIsEnabled)
    private var sourceControlIsEnabled

    @AppStorage(Islands.BackgroundImageKey.path)
    private var backgroundImagePath = ""

    @AppStorage(Islands.BackgroundImageKey.opacity)
    private var backgroundImageOpacity = Islands.BackgroundImageKey.defaultOpacity

    @AppStorage(Islands.densityKey)
    private var density = Islands.Density.compact.rawValue

    @State private var themeModel: ThemeModel = .shared

    @State private var backgroundImage: NSImage? = nil

    @FocusState private var focusedEditor: Editor?

    private var frameOpacity: Double {
        backgroundImage == nil ? 1 : 1 - backgroundImageOpacity
    }

    var body: some View {
        ZStack {
            BackgroundImageLayer(image: backgroundImage)
                .ignoresSafeArea()
            Islands.frame
                .opacity(frameOpacity)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ToolWindowStripe()
                    islandsColumn
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                StatusBarView()
            }
        }
        .id(density)
        .task(id: backgroundImagePath) {
            backgroundImage = BackgroundImageLayer.loadImage(at: backgroundImagePath)
        }
        .onChange(of: toolWindowManager.placement) { _, _ in
            saveLayout()
        }
        .onChange(of: toolWindowManager.bottomMaximized) { _, _ in
            saveLayout()
        }
        .onChange(of: utilityAreaViewModel.isCollapsed) { _, isCollapsed in
            if isCollapsed {
                if toolWindowManager.isVisible(.terminal) {
                    toolWindowManager.hide(.terminal)
                }
            } else {
                toolWindowManager.show(Self.utilityWindow(showingOutput: taskManager.taskShowingOutput != nil))
            }
        }
        .onChange(of: taskManager.taskShowingOutput) { _, output in
            if output != nil {
                toolWindowManager.show(.run)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("workspace area")
    }

    private var islandsColumn: some View {
        GeometryReader { geometry in
            GlassEffectContainer(spacing: 0) {
                columnContent(available: geometry.size)
            }
        }
        .padding(.top, Islands.islandGap)
        .padding(.trailing, Islands.islandGap)
        .padding(.bottom, Islands.islandGap)
    }

    @ViewBuilder
    private func columnContent(available: CGSize) -> some View {
        VStack(spacing: 0) {
            if toolWindowManager.bottomMaximized, toolWindowManager.active(.bottom) != nil {
                anchorGroup(.bottom)
                    .frame(maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    if toolWindowManager.active(.left) != nil {
                        anchorGroup(.left)
                            .frame(width: ToolWindowLayout.clampLeftWidth(
                                toolWindowManager.leftWidth,
                                availableWidth: available.width
                            ))
                        leftResizeHandle(availableWidth: available.width)
                    }
                    editorIsland
                }
                .frame(maxHeight: .infinity)

                if toolWindowManager.active(.bottom) != nil {
                    bottomResizeHandle(availableHeight: available.height)
                    anchorGroup(.bottom)
                        .frame(height: ToolWindowLayout.clampBottomHeight(
                            toolWindowManager.bottomHeight,
                            availableHeight: available.height
                        ))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func anchorGroup(_ anchor: ToolWindowAnchor) -> some View {
        let main = toolWindowManager.visible(on: anchor, side: .main)
        let split = toolWindowManager.visible(on: anchor, side: .split)
        if let main, let split {
            GeometryReader { geometry in
                let isStacked = anchor.splitsVertically
                let total = isStacked ? geometry.size.height : geometry.size.width
                let sizes = ToolWindowSplitState.partSizes(
                    total: total,
                    proportion: toolWindowManager.mainProportion(on: anchor),
                    gap: Islands.islandGap,
                    minimumPart: ToolWindowLayout.minSplitPart
                )
                if isStacked {
                    VStack(spacing: 0) {
                        toolWindowIsland(main)
                            .frame(height: sizes.first)
                        splitHandle(anchor: anchor, total: total)
                            .frame(maxWidth: .infinity)
                            .frame(height: Islands.islandGap)
                        toolWindowIsland(split)
                            .frame(height: sizes.second)
                    }
                } else {
                    HStack(spacing: 0) {
                        toolWindowIsland(main)
                            .frame(width: sizes.first)
                        splitHandle(anchor: anchor, total: total)
                            .frame(width: Islands.islandGap)
                            .frame(maxHeight: .infinity)
                        toolWindowIsland(split)
                            .frame(width: sizes.second)
                    }
                }
            }
        } else if let only = main ?? split {
            toolWindowIsland(only)
        }
    }

    private func splitHandle(anchor: ToolWindowAnchor, total: CGFloat) -> some View {
        IslandResizeHandle(
            orientation: anchor.splitsVertically ? .horizontal : .vertical,
            onDrag: toolWindowManager.splitDividerDrag(on: anchor, total: total),
            onDragEnded: saveLayout
        )
    }

    private func toolWindowIsland(_ id: ToolWindowID) -> some View {
        ToolWindowContentView(id: id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassIsland()
    }

    private func leftResizeHandle(availableWidth: CGFloat) -> some View {
        IslandResizeHandle(
            orientation: .vertical,
            onDrag: toolWindowManager.leftResizeDrag(availableWidth: availableWidth),
            onDragEnded: saveLayout
        )
        .frame(width: Islands.islandGap)
        .frame(maxHeight: .infinity)
    }

    private func bottomResizeHandle(availableHeight: CGFloat) -> some View {
        IslandResizeHandle(
            orientation: .horizontal,
            onDrag: toolWindowManager.bottomResizeDrag(availableHeight: availableHeight),
            onDragEnded: saveLayout
        )
        .frame(maxWidth: .infinity)
        .frame(height: Islands.islandGap)
    }

    private var editorIsland: some View {
        EditorLayoutView(
            layout: editorManager.displayedLayout,
            focus: $focusedEditor
        )
        .environment(\.isEditorLayoutAtEdge, VerticalEdge.Set())
        .onChange(of: editorManager.activeEditor) { _, newValue in
            focusedEditor = newValue
        }
        .onChange(of: focusedEditor) { _, focused in editorManager.adoptFocus(of: focused) }
        .task {
            themeModel.colorScheme = colorScheme
        }
        .onChange(of: colorScheme, themeModel.colorSchemeAdoption(matchAppearance: matchAppearance))
        .task { await Self.refreshGitData(enabled: sourceControlIsEnabled, in: workspace) }
        .onChange(of: sourceControlIsEnabled, Self.branchSync(in: workspace))
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { output in
            Self.recordWindowSize(closing: output.object, window: window, in: workspace)
        }
        .onDrop(of: [.fileURL], isTargeted: nil, perform: Self.dropHandler(editorManager: editorManager))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if let sourceControlManager = workspace.sourceControlManager {
                WorkspaceSheets()
                    .environment(sourceControlManager)
            }
        }
        .island()
        .overlay(alignment: .topTrailing) {
            NotificationPanelView()
        }
    }

    private func saveLayout() {
        ToolWindowLayout(manager: toolWindowManager).save(to: workspace)
    }

    static func openDroppedFiles(_ providers: [NSItemProvider], in editorManager: EditorManager) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }

                Task { @MainActor in
                    let file = CEWorkspaceFile(url: url)
                    editorManager.activeEditor.openTab(file: file)
                }
            }
        }
        return true
    }

    static func recordWindowSize(closing object: Any?, window: NSWindow?, in workspace: WorkspaceDocument) {
        if let closingWindow = object as? NSWindow, window == closingWindow {
            workspace.addToWorkspaceState(
                key: .workspaceWindowSize,
                value: NSStringFromRect(closingWindow.frame)
            )
        }
    }

    static func refreshRemotesAndStashes(_ manager: SourceControlManager) async throws {
        try await manager.refreshRemotes()
        try await manager.refreshStashEntries()
    }

    static func refreshGitData(
        enabled: Bool,
        in workspace: WorkspaceDocument,
        refresh: (SourceControlManager) async throws -> Void = IslandsWorkspaceView.refreshRemotesAndStashes
    ) async {
        guard enabled, let sourceControlManager = workspace.sourceControlManager else { return }
        do {
            try await refresh(sourceControlManager)
        } catch {
            await sourceControlManager.showAlertForError(
                title: "Error refreshing Git data",
                error: error
            )
        }
    }

    static func syncCurrentBranch(_ enabled: Bool, in workspace: WorkspaceDocument) async {
        guard let sourceControlManager = workspace.sourceControlManager else { return }
        if enabled {
            await sourceControlManager.refreshCurrentBranch()
        } else {
            sourceControlManager.currentBranch = nil
        }
    }

    static func utilityWindow(showingOutput: Bool) -> ToolWindowID {
        showingOutput ? .run : .terminal
    }

    static func dropHandler(editorManager: EditorManager) -> ([NSItemProvider]) -> Bool {
        { openDroppedFiles($0, in: editorManager) }
    }

    static func branchSync(in workspace: WorkspaceDocument) -> (Bool, Bool) -> Void {
        { _, enabled in
            Task { await syncCurrentBranch(enabled, in: workspace) }
        }
    }
}

extension EditorManager {
    func adoptFocus(of editor: Editor?) {
        if let editor, activeEditor != editor {
            activeEditor = editor
        }
    }

    var displayedLayout: EditorLayout {
        guard isFocusingActiveEditor else { return editorLayout }
        return activeEditor.getEditorLayout() ?? editorLayout
    }
}

extension ThemeModel {
    func adopt(_ newValue: ColorScheme, matchAppearance: Bool) {
        colorScheme = newValue
        if matchAppearance {
            selectedTheme = newValue == .dark ? selectedDarkTheme : selectedLightTheme
        }
    }

    func colorSchemeAdoption(matchAppearance: Bool) -> (ColorScheme, ColorScheme) -> Void {
        { _, newValue in self.adopt(newValue, matchAppearance: matchAppearance) }
    }
}

extension ToolWindowManager {
    func resizeLeft(by delta: CGFloat, availableWidth: CGFloat) {
        leftWidth = ToolWindowLayout.clampLeftWidth(leftWidth + delta, availableWidth: availableWidth)
    }

    func resizeBottom(by delta: CGFloat, availableHeight: CGFloat) {
        bottomHeight = ToolWindowLayout.clampBottomHeight(bottomHeight - delta, availableHeight: availableHeight)
    }

    func moveSplitDivider(on anchor: ToolWindowAnchor, by delta: CGFloat, total: CGFloat) {
        let proportion = ToolWindowSplitState.proportion(
            movingDividerBy: delta,
            from: mainProportion(on: anchor),
            total: total,
            gap: Islands.islandGap,
            minimumPart: ToolWindowLayout.minSplitPart
        )
        setMainProportion(on: anchor, proportion)
    }

    func splitDividerDrag(on anchor: ToolWindowAnchor, total: CGFloat) -> (CGFloat) -> Void {
        { self.moveSplitDivider(on: anchor, by: $0, total: total) }
    }

    func leftResizeDrag(availableWidth: CGFloat) -> (CGFloat) -> Void {
        { self.resizeLeft(by: $0, availableWidth: availableWidth) }
    }

    func bottomResizeDrag(availableHeight: CGFloat) -> (CGFloat) -> Void {
        { self.resizeBottom(by: $0, availableHeight: availableHeight) }
    }
}
