//
//  EditorTabView.swift
//  Dreamder
//
//  Created by Lukas Pistrol on 17.03.22.
//

import SwiftUI

struct EditorTabContext {
    let file: CEWorkspaceFile
    let editor: Editor
    let editorManager: EditorManager
    let workspace: WorkspaceDocument

    var isTemporary: Bool {
        editor.temporaryTab?.file == file
    }
}

@MainActor
@Observable
final class EditorTabInteraction {
    static let middleButtonNumber = 2

    var isHovering = false
    var isHoveringClose = false
    private(set) var isPressing = false
    @ObservationIgnored var context: EditorTabContext?

    func hoverChanged(_ hover: Bool) {
        isHovering = hover
        if !hover {
            isHoveringClose = false
        }
        Task {
            if hover {
                NSCursor.arrow.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    func pressBegan() {
        if !isHoveringClose {
            isPressing = true
        }
    }

    func pressEnded(_ context: EditorTabContext) {
        if isPressing {
            select(context)
        }
        isPressing = false
    }

    func select(_ context: EditorTabContext) {
        context.editorManager.activeEditor = context.editor
        if context.editor.selectedTab?.file != context.file {
            let tabItem = EditorInstance(workspace: context.workspace, file: context.file)
            context.editor.setSelectedTab(context.file)
            context.editor.clearFuture()
            context.editor.addToHistory(tabItem)
        }
    }

    func close(_ context: EditorTabContext) {
        context.editor.closeTab(file: context.file)
    }

    func unpin(_ context: EditorTabContext) {
        context.editor.setPinned(false, file: context.file)
    }

    func unpinTab() {
        guard let context else { return }
        unpin(context)
    }

    func closeTab() {
        guard let context else { return }
        close(context)
    }

    func dragChanged(_ value: some PointerLocated) {
        pressBegan()
    }

    func dragEnded(_ value: some PointerLocated) {
        guard let context else { return }
        pressEnded(context)
    }

    func doubleTapEnded(_ value: Void) {
        guard let context else { return }
        doubleTapped(context)
    }

    func doubleTapped(_ context: EditorTabContext) {
        if context.isTemporary {
            context.editor.temporaryTab = nil
        }
    }

    func middleClicked(buttonNumber: Int, _ context: EditorTabContext) {
        guard isHovering, buttonNumber == Self.middleButtonNumber else { return }
        Task {
            context.editor.closeTabUnlessPinned(file: context.file)
        }
    }

    func monitored(_ event: NSEvent, _ context: EditorTabContext) -> NSEvent? {
        middleClicked(buttonNumber: event.buttonNumber, context)
        return event
    }
}

struct EditorTabView: View {
    @Environment(\.controlActiveState)
    private var activeState

    @Environment(\.isActiveEditor)
    private var isActiveEditor

    @Environment(WorkspaceDocument.self) private var workspace
    @Environment(EditorManager.self) private var editorManager
    @Environment(Editor.self) private var editor

    @State private var fileObserver: EditorTabFileObserver

    static var tabHeight: CGFloat {
        Islands.tabPillHeight
    }

    @State private var interaction: EditorTabInteraction

    @State private var keyMonitor: Any?

    private var isDocumentEdited: Bool {
        tabFile.fileDocument?.isEdited ?? false
    }

    private var draggingTabId: CEWorkspaceFile.ID?

    @Binding private var closeButtonGestureActive: Bool

    private let tabFile: CEWorkspaceFile

    var index: Int

    private var context: EditorTabContext {
        EditorTabContext(file: tabFile, editor: editor, editorManager: editorManager, workspace: workspace)
    }

    private var isTemporary: Bool {
        editor.temporaryTab?.file == tabFile
    }

    private var isPinned: Bool {
        editor.isPinned(tabFile)
    }

    private var isActive: Bool {
        tabFile == editor.selectedTab?.file
    }

    private var isDragging: Bool {
        draggingTabId == tabFile.id
    }

    private var isInHoldingState: Bool {
        interaction.isPressing || isDragging
    }

    private var isFocused: Bool {
        activeState != .inactive && isActiveEditor
    }

    private var showsCloseButton: Bool {
        isActive || interaction.isHovering || isInHoldingState
    }

    private var isTestFile: Bool {
        TestFileClassifier.isTestFile(tabFile.url)
    }

    private var backgroundColor: Color {
        if isActive {
            return isFocused ? Islands.tabSelectedBackground : Islands.tabInactiveSelectedBackground
        }
        return .clear
    }

    private var showsHoverCapsule: Bool {
        !isActive && (interaction.isHovering || isInHoldingState)
    }

    @ViewBuilder private var fileColorFill: some View {
        if isTestFile, isActive {
            RoundedRectangle(
                cornerRadius: max(Islands.tabPillRadius - Islands.tabColorInset, 1),
                style: .continuous
            )
            .fill(Islands.testFileBackground.opacity(isFocused ? 1 : 0.4))
            .padding(Islands.tabColorInset)
        }
    }

    private var borderColor: Color {
        guard isActive else { return .clear }
        return isFocused ? Islands.tabSelectedBorder : Islands.tabInactiveSelectedBorder
    }

    init(
        file: CEWorkspaceFile,
        index: Int,
        draggingTabId: CEWorkspaceFile.ID?,
        closeButtonGestureActive: Binding<Bool>,
        interaction: EditorTabInteraction = EditorTabInteraction()
    ) {
        self.tabFile = file
        self.index = index
        self.draggingTabId = draggingTabId
        self._closeButtonGestureActive = closeButtonGestureActive
        self._fileObserver = State(wrappedValue: EditorTabFileObserver(file: file))
        self._interaction = State(wrappedValue: interaction)
    }

    private func middleClickMonitor() -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { interaction.monitored($0, context) }
    }

    @ViewBuilder private var trailingSlot: some View {
        HStack(spacing: 2) {
            if isDocumentEdited {
                Circle()
                    .fill(Islands.secondaryForeground)
                    .frame(width: 6, height: 6)
            }
            if isPinned {
                EditorTabPinButton(
                    unpinAction: interaction.unpinTab,
                    isHoveringClose: $interaction.isHoveringClose
                )
            } else if showsCloseButton {
                EditorTabCloseButton(
                    closeAction: interaction.closeTab,
                    closeButtonGestureActive: $closeButtonGestureActive,
                    isHoveringClose: $interaction.isHoveringClose
                )
            }
        }
        .frame(width: isDocumentEdited && (showsCloseButton || isPinned) ? 20 : 16, height: 16)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(IntelliJIcon.fileIcon(for: tabFile.name))
                .resizable()
                .frame(width: 16, height: 16)
            Text(tabFile.name)
                .font(isTemporary ? Islands.tabLabelFont.italic() : Islands.tabLabelFont)
                .foregroundStyle(isActive ? Islands.foreground : Islands.foreground.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 240, alignment: .leading)
                .strikethrough(fileObserver.isDeleted, color: Islands.secondaryForeground)
            trailingSlot
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(height: Self.tabHeight)
        .background(
            RoundedRectangle(cornerRadius: Islands.tabPillRadius, style: .continuous)
                .fill(backgroundColor)
                .overlay(fileColorFill)
        )
        .background {
            if showsHoverCapsule {
                Capsule()
                    .fill(Islands.tabHoverFill)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Islands.tabPillRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(tabFile.name)
        .onHover(perform: interaction.hoverChanged)
        .onAppear {
            keyMonitor = middleClickMonitor()
        }
        .onDisappear {
            if let keyMonitor = keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged(interaction.dragChanged)
                .onEnded(interaction.dragEnded)
        )
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded(interaction.doubleTapEnded)
        )
        .zIndex(isActive ? 2 : (isDragging ? 3 : (interaction.isPressing ? 1 : 0)))
        .id(tabFile.id)
        .tabBarContextMenu(item: tabFile, isTemporary: isTemporary)
        .accessibilityElement(children: .contain)
        .onAppear {
            interaction.context = context
            workspace.workspaceFileManager?.addObserver(fileObserver)
        }
        .onDisappear {
            workspace.workspaceFileManager?.removeObserver(fileObserver)
        }
    }
}
