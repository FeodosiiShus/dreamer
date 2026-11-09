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
            let metrics = Islands.layoutMetrics
            let inner = metrics.innerSize(of: geometry.size)
            GlassEffectContainer(spacing: 0) {
                IslandsColumnLayout(metrics: metrics, input: layoutInput) {
                    columnContent(available: inner)
                }
            }
        }
    }

    private var layoutInput: IslandsLayoutMetrics.Input {
        IslandsLayoutMetrics.Input(
            hasLeft: toolWindowManager.active(.left) != nil,
            leftWidth: toolWindowManager.leftWidth,
            hasBottom: toolWindowManager.active(.bottom) != nil,
            bottomHeight: toolWindowManager.bottomHeight,
            bottomMaximized: toolWindowManager.bottomMaximized
        )
    }

    @ViewBuilder
    private func columnContent(available: CGSize) -> some View {
        let input = layoutInput
        if input.bottomMaximized, input.hasBottom {
            anchorGroup(.bottom)
                .islandSlot(.bottom)
        } else {
            if input.hasLeft {
                anchorGroup(.left)
                    .islandSlot(.left)
                leftResizeHandle(availableWidth: available.width)
                    .islandSlot(.leftDivider)
            }
            editorIsland
                .islandSlot(.editor)
            if input.hasBottom {
                bottomResizeHandle(availableHeight: available.height)
                    .islandSlot(.bottomDivider)
                anchorGroup(.bottom)
                    .islandSlot(.bottom)
            }
        }
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
    }

    private func bottomResizeHandle(availableHeight: CGFloat) -> some View {
        IslandResizeHandle(
            orientation: .horizontal,
            onDrag: toolWindowManager.bottomResizeDrag(availableHeight: availableHeight),
            onDragEnded: saveLayout
        )
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
