//
//  EditorTabView.swift
//  Dreamder
//
//  Created by Lukas Pistrol on 17.03.22.
//

import Combine
import SwiftUI

struct EditorTabView: View {
    @Environment(\.controlActiveState)
    private var activeState

    @Environment(\.isActiveEditor)
    private var isActiveEditor

    @EnvironmentObject var workspace: WorkspaceDocument
    @EnvironmentObject private var editorManager: EditorManager
    @EnvironmentObject private var editor: Editor

    @StateObject private var fileObserver: EditorTabFileObserver

    static var tabHeight: CGFloat {
        Islands.tabPillHeight
    }

    @State private var isHovering: Bool = false

    @State private var isHoveringClose: Bool = false

    @State private var isPressing: Bool = false

    @State private var keyMonitor: Any?

    @State private var isDocumentEdited: Bool = false

    private var draggingTabId: CEWorkspaceFile.ID?

    @Binding private var closeButtonGestureActive: Bool

    private let tabFile: CEWorkspaceFile

    var index: Int

    private var isTemporary: Bool {
        editor.temporaryTab?.file == tabFile
    }

    private var isActive: Bool {
        tabFile == editor.selectedTab?.file
    }

    private var isDragging: Bool {
        draggingTabId == tabFile.id
    }

    private var isInHoldingState: Bool {
        isPressing || isDragging
    }

    private var isFocused: Bool {
        activeState != .inactive && isActiveEditor
    }

    private var showsCloseButton: Bool {
        isActive || isHovering || isInHoldingState
    }

    private var isTestFile: Bool {
        TestFileClassifier.isTestFile(tabFile.url)
    }

    private var backgroundColor: Color {
        if isActive {
            return isFocused ? Islands.tabSelectedBackground : Islands.tabInactiveSelectedBackground
        }
        if isHovering || isInHoldingState {
            return Islands.actionHover
        }
        return isTestFile ? Islands.testFileBackground.opacity(0.4) : .clear
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

    private func switchAction() {
        editorManager.activeEditor = editor
        if editor.selectedTab?.file != tabFile {
            let tabItem = EditorInstance(workspace: workspace, file: tabFile)
            editor.setSelectedTab(tabFile)
            editor.clearFuture()
            editor.addToHistory(tabItem)
        }
    }

    func closeAction() {
        editor.closeTab(file: tabFile)
    }

    init(
        file: CEWorkspaceFile,
        index: Int,
        draggingTabId: CEWorkspaceFile.ID?,
        closeButtonGestureActive: Binding<Bool>
    ) {
        self.tabFile = file
        self.index = index
        self.draggingTabId = draggingTabId
        self._closeButtonGestureActive = closeButtonGestureActive
        self._fileObserver = StateObject(wrappedValue: EditorTabFileObserver(file: file))
    }

    @ViewBuilder private var trailingSlot: some View {
        HStack(spacing: 2) {
            if isDocumentEdited {
                Circle()
                    .fill(Islands.secondaryForeground)
                    .frame(width: 6, height: 6)
            }
            if showsCloseButton {
                EditorTabCloseButton(
                    closeAction: closeAction,
                    closeButtonGestureActive: $closeButtonGestureActive,
                    isHoveringClose: $isHoveringClose
                )
            }
        }
        .frame(width: isDocumentEdited && showsCloseButton ? 20 : 16, height: 16)
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
        .overlay(
            RoundedRectangle(cornerRadius: Islands.tabPillRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(tabFile.name)
        .onHover { hover in
            isHovering = hover
            if !hover {
                isHoveringClose = false
            }
            DispatchQueue.main.async {
                if hover {
                    NSCursor.arrow.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { event in
                if self.isHovering && event.type == .otherMouseDown && event.buttonNumber == 2 {
                    DispatchQueue.main.async {
                        editor.closeTab(file: tabFile)
                    }
                }
                return event
            }
        }
        .onDisappear {
            if let keyMonitor = keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged({ _ in
                    if !isHoveringClose {
                        isPressing = true
                    }
                })
                .onEnded({ _ in
                    if isPressing {
                        switchAction()
                    }
                    isPressing = false
                })
        )
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { _ in
                    if isTemporary {
                        editor.temporaryTab = nil
                    }
                }
        )
        .zIndex(isActive ? 2 : (isDragging ? 3 : (isPressing ? 1 : 0)))
        .id(tabFile.id)
        .tabBarContextMenu(item: tabFile, isTemporary: isTemporary)
        .accessibilityElement(children: .contain)
        .onAppear {
            workspace.workspaceFileManager?.addObserver(fileObserver)
            isDocumentEdited = tabFile.fileDocument?.isDocumentEdited ?? false
        }
        .onDisappear {
            workspace.workspaceFileManager?.removeObserver(fileObserver)
        }
        .onReceive(tabFile.fileDocumentPublisher) { _ in
            isDocumentEdited = tabFile.fileDocument?.isDocumentEdited ?? false
        }
        .onReceive(
            tabFile.fileDocument?.isDocumentEditedPublisher.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()
        ) { isDocumentEdited = $0 }
    }
}
