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
        .onChange(of: toolWindowManager.visible) { _, _ in
            saveLayout()
        }
        .onChange(of: toolWindowManager.bottomMaximized) { _, _ in
            saveLayout()
        }
        .onChange(of: utilityAreaViewModel.isCollapsed) { _, isCollapsed in
            if isCollapsed {
                if toolWindowManager.active(.bottom) == .terminal {
                    toolWindowManager.hide(.bottom)
                }
            } else {
                toolWindowManager.show(taskManager.taskShowingOutput == nil ? .terminal : .run)
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
            glassContainer {
                columnContent(available: geometry.size)
            }
        }
        .padding(.top, Islands.islandGap)
        .padding(.trailing, Islands.islandGap)
        .padding(.bottom, Islands.islandGap)
    }

    @ViewBuilder
    private func glassContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 0) {
                content()
            }
        } else {
            content()
        }
    }

    @ViewBuilder
    private func columnContent(available: CGSize) -> some View {
        VStack(spacing: 0) {
            if toolWindowManager.bottomMaximized, let bottom = toolWindowManager.active(.bottom) {
                toolWindowIsland(bottom)
                    .frame(maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    if let left = toolWindowManager.active(.left) {
                        toolWindowIsland(left)
                            .frame(width: ToolWindowLayout.clampLeftWidth(
                                toolWindowManager.leftWidth,
                                availableWidth: available.width
                            ))
                        leftResizeHandle(availableWidth: available.width)
                    }
                    editorIsland
                }
                .frame(maxHeight: .infinity)

                if let bottom = toolWindowManager.active(.bottom) {
                    bottomResizeHandle(availableHeight: available.height)
                    toolWindowIsland(bottom)
                        .frame(height: ToolWindowLayout.clampBottomHeight(
                            toolWindowManager.bottomHeight,
                            availableHeight: available.height
                        ))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func toolWindowIsland(_ id: ToolWindowID) -> some View {
        let content = ToolWindowContentView(id: id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        return Group {
            if id == .project {
                content.island()
            } else {
                content.glassIsland()
            }
        }
    }

    private func leftResizeHandle(availableWidth: CGFloat) -> some View {
        IslandResizeHandle(
            orientation: .vertical,
            onDrag: { delta in
                toolWindowManager.leftWidth = ToolWindowLayout.clampLeftWidth(
                    toolWindowManager.leftWidth + delta,
                    availableWidth: availableWidth
                )
            },
            onDragEnded: saveLayout
        )
        .frame(width: Islands.islandGap)
        .frame(maxHeight: .infinity)
    }

    private func bottomResizeHandle(availableHeight: CGFloat) -> some View {
        IslandResizeHandle(
            orientation: .horizontal,
            onDrag: { delta in
                toolWindowManager.bottomHeight = ToolWindowLayout.clampBottomHeight(
                    toolWindowManager.bottomHeight - delta,
                    availableHeight: availableHeight
                )
            },
            onDragEnded: saveLayout
        )
        .frame(maxWidth: .infinity)
        .frame(height: Islands.islandGap)
    }

    private var editorIsland: some View {
        EditorLayoutView(
            layout: editorManager.isFocusingActiveEditor
                ? editorManager.activeEditor.getEditorLayout() ?? editorManager.editorLayout
                : editorManager.editorLayout,
            focus: $focusedEditor
        )
        .environment(\.isEditorLayoutAtEdge, VerticalEdge.Set())
        .onChange(of: editorManager.activeEditor) { _, newValue in
            focusedEditor = newValue
        }
        .onChange(of: focusedEditor) { _, newValue in
            if let newValue, editorManager.activeEditor != newValue {
                editorManager.activeEditor = newValue
            }
        }
        .task {
            themeModel.colorScheme = colorScheme
        }
        .onChange(of: colorScheme) { _, newValue in
            themeModel.colorScheme = newValue
            if matchAppearance {
                themeModel.selectedTheme = newValue == .dark
                    ? themeModel.selectedDarkTheme
                    : themeModel.selectedLightTheme
            }
        }
        .task {
            guard sourceControlIsEnabled, let sourceControlManager = workspace.sourceControlManager else {
                return
            }
            do {
                try await sourceControlManager.refreshRemotes()
                try await sourceControlManager.refreshStashEntries()
            } catch {
                await sourceControlManager.showAlertForError(
                    title: "Error refreshing Git data",
                    error: error
                )
            }
        }
        .onChange(of: sourceControlIsEnabled) { _, newValue in
            guard let sourceControlManager = workspace.sourceControlManager else { return }
            if newValue {
                Task {
                    await sourceControlManager.refreshCurrentBranch()
                }
            } else {
                sourceControlManager.currentBranch = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { output in
            if let closingWindow = output.object as? NSWindow, self.window == closingWindow {
                workspace.addToWorkspaceState(
                    key: .workspaceWindowSize,
                    value: NSStringFromRect(closingWindow.frame)
                )
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
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

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }

                DispatchQueue.main.async {
                    let file = CEWorkspaceFile(url: url)
                    editorManager.activeEditor.openTab(file: file)
                }
            }
        }
        return true
    }
}
