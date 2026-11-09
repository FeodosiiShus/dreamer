//
//  EditorTabs.swift
//  Dreamder
//
//  Created by Austin Condiff on 9/7/23.
//

import SwiftUI

@MainActor
@Observable
final class EditorTabStripModel {
    typealias TabID = CEWorkspaceFile.ID

    static let tabSpacing: CGFloat = 4
    static let dragReleaseDelay: Duration = .milliseconds(250)
    static let dragCommitDelay: Duration = .milliseconds(400)
    static let dragUpdateThreshold: CGFloat = 10

    var draggingTabId: TabID?
    var draggingStartLocation: CGFloat?
    var draggingLastLocation: CGFloat?
    var openedTabs: [TabID] = []
    var pinnedTabs: Set<TabID> = []
    var tabWidth: [TabID: CGFloat] = [:]
    var tabLocations: [TabID: CGRect] = [:]
    var tabOffsets: [TabID: CGFloat] = [:]
    var closeButtonGestureActive = false
    var revealedTabID: TabID?
    var viewportFrame: CGRect = .zero

    func synchronizeTabs(with editor: Editor) {
        openedTabs = editor.tabs.map(\.file.id)
        pinnedTabs = Set(editor.tabs.filter { editor.isPinned($0.file) }.map(\.file.id))
    }

    func hiddenTabs(in viewport: CGRect) -> [TabID] {
        EditorTabOverflow.hiddenTabs(openedTabs: openedTabs, frames: tabLocations, viewport: viewport)
    }

    @discardableResult
    func activate(_ id: TabID, in editor: Editor, editorManager: EditorManager) -> Bool {
        guard let tab = editor.tabs.first(where: { $0.file.id == id }) else { return false }
        editorManager.activeEditor = editor
        editor.setSelectedTab(tab.file)
        editor.clearFuture()
        editor.addToHistory(tab)
        return true
    }

    func reveal(_ id: TabID, in editor: Editor, editorManager: EditorManager) {
        guard activate(id, in: editor, editorManager: editorManager) else { return }
        revealedTabID = id
    }

    func dragChanged(id: TabID, startX: CGFloat, currentX: CGFloat) {
        if closeButtonGestureActive {
            return
        }

        if draggingTabId != id {
            draggingTabId = id
            draggingStartLocation = startX
            draggingLastLocation = currentX
        }
        guard let startLocation = draggingStartLocation,
              let currentIndex = openedTabs.firstIndex(of: id),
              let currentTabWidth = tabWidth[id],
              let lastLocation = draggingLastLocation
        else { return }
        let dragDifference = currentX - lastLocation
        tabOffsets[id] = currentX - startLocation
        if currentIndex > 0 && dragDifference < 0 {
            let previousTabIndex = currentIndex - 1
            let previousID = openedTabs[previousTabIndex]
            guard pinnedTabs.contains(previousID) == pinnedTabs.contains(id) else { return }
            guard let previousTabLocation = tabLocations[openedTabs[previousTabIndex]],
                  let previousTabWidth = tabWidth[openedTabs[previousTabIndex]]
            else { return }
            if currentX < max(
                previousTabLocation.maxX - previousTabWidth * 0.1,
                previousTabLocation.minX + currentTabWidth * 0.9
            ) {
                let changing = previousTabWidth + Self.tabSpacing
                draggingStartLocation = startLocation - changing
                withAnimation {
                    tabOffsets[id]? += changing
                    openedTabs.move(
                        fromOffsets: IndexSet(integer: previousTabIndex),
                        toOffset: currentIndex + 1
                    )
                }
                return
            }
        }
        if currentIndex < openedTabs.count - 1 && dragDifference > 0 {
            let nextTabIndex = currentIndex + 1
            let nextID = openedTabs[nextTabIndex]
            guard pinnedTabs.contains(nextID) == pinnedTabs.contains(id) else { return }
            guard let nextTabLocation = tabLocations[openedTabs[nextTabIndex]],
                  let nextTabWidth = tabWidth[openedTabs[nextTabIndex]]
            else { return }
            if currentX > min(
                nextTabLocation.minX + nextTabWidth * 0.1,
                nextTabLocation.maxX - currentTabWidth * 0.9
            ) {
                let changing = nextTabWidth + Self.tabSpacing
                draggingStartLocation = startLocation + changing
                withAnimation {
                    tabOffsets[id]? -= changing
                    openedTabs.move(
                        fromOffsets: IndexSet(integer: nextTabIndex),
                        toOffset: currentIndex
                    )
                }
                return
            }
        }
        if abs(currentX - lastLocation) >= Self.dragUpdateThreshold {
            draggingLastLocation = currentX
        }
    }

    func dragEnded(editor: Editor) {
        draggingStartLocation = nil
        draggingLastLocation = nil
        withAnimation(.easeInOut(duration: 0.25)) {
            tabOffsets = [:]
        }
        Task {
            try? await Task.sleep(for: Self.dragReleaseDelay)
            draggingTabId = nil
        }
        Task {
            try? await Task.sleep(for: Self.dragCommitDelay)
            if draggingStartLocation == nil {
                editor.tabs = .init(openedTabs.compactMap { id in
                    editor.tabs.first { $0.file.id == id }
                })
            }
        }
    }
}

struct EditorTabs: View {
    typealias TabID = CEWorkspaceFile.ID

    @Environment(Editor.self) private var editor
    @Environment(EditorManager.self) private var editorManager

    @State private var strip: EditorTabStripModel

    @State private var scrollOffset: CGFloat = 0

    @State private var scrollTrailingOffset: CGFloat? = 0

    init(strip: EditorTabStripModel = EditorTabStripModel()) {
        _strip = State(initialValue: strip)
    }

    private func makeTabDragGesture(id: TabID) -> some Gesture {
        let handler = EditorTabDragHandler(id: id, strip: strip, editor: editor)
        return DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged(handler.changed)
            .onEnded(handler.ended)
    }

    private func makeTabItemGeometryReader(id: TabID) -> some View {
        GeometryReader { tabItemGeoReader in
            Rectangle()
                .foregroundColor(.clear)
                .onAppear {
                    strip.tabWidth[id] = tabItemGeoReader.size.width
                    strip.tabLocations[id] = tabItemGeoReader.frame(in: .global)
                }
                .onChange(of: tabItemGeoReader.frame(in: .global)) { _, tabCGRect in
                    strip.tabLocations[id] = tabCGRect
                }
                .onChange(of: tabItemGeoReader.size.width) { _, newWidth in
                    strip.tabWidth[id] = newWidth
                }
        }
    }

    private func showHiddenTabsButton(_ hidden: [TabID]) -> some View {
        Menu {
            EditorHiddenTabsMenuContent(hidden: hidden, strip: strip, editor: editor, editorManager: editorManager)
        } label: {
            Image("general/chevronDown")
                .resizable()
                .frame(width: 16, height: 16)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.trailing, 2)
        .help("Show Hidden Tabs")
    }

    var body: some View {
        ScrollViewReader { scrollReader in
            HStack(spacing: 0) {
                TrackableScrollView(
                    .horizontal,
                    showIndicators: false,
                    contentOffset: $scrollOffset,
                    contentTrailingOffset: $scrollTrailingOffset
                ) {
                    HStack(spacing: EditorTabStripModel.tabSpacing) {
                        ForEach(Array(strip.openedTabs.enumerated()), id: \.element) { index, id in
                            if let item = editor.tabs.first(where: { $0.file.id == id }) {
                                EditorTabView(
                                    file: item.file,
                                    index: index,
                                    draggingTabId: strip.draggingTabId,
                                    closeButtonGestureActive: $strip.closeButtonGestureActive
                                )
                                .fixedSize()
                                .transition(
                                    .asymmetric(
                                        insertion: .offset(x: -14).combined(with: .opacity),
                                        removal: .opacity
                                    )
                                )
                                .background(makeTabItemGeometryReader(id: id))
                                .offset(x: strip.tabOffsets[id] ?? 0, y: 0)
                                .simultaneousGesture(makeTabDragGesture(id: id), including: .all)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .onAppear {
                        strip.synchronizeTabs(with: editor)
                        scrollReader.scrollTo(editor.selectedTab?.file.id)
                    }
                    .onChange(of: editor.pinnedURLs) {
                        strip.synchronizeTabs(with: editor)
                    }
                    .onChange(of: editor.tabs) { tabs, newValue in
                        if tabs.count == newValue.count {
                            strip.synchronizeTabs(with: editor)
                        } else {
                            withAnimation(.easeOut(duration: 0.20)) {
                                strip.synchronizeTabs(with: editor)
                            }
                        }
                        Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            withAnimation {
                                scrollReader.scrollTo(editor.selectedTab?.file.id)
                            }
                        }
                    }
                    .onChange(of: editor.selectedTab) { _, newValue in
                        withAnimation {
                            scrollReader.scrollTo(newValue?.file.id)
                        }
                    }
                    .onChange(of: strip.revealedTabID) { _, id in
                        guard let id else { return }
                        withAnimation {
                            scrollReader.scrollTo(id, anchor: .trailing)
                        }
                        strip.revealedTabID = nil
                    }
                }
                .background(
                    GeometryReader { viewportProxy in
                        Color.clear
                            .onAppear { strip.viewportFrame = viewportProxy.frame(in: .global) }
                            .onChange(of: viewportProxy.frame(in: .global)) { _, frame in
                                strip.viewportFrame = frame
                            }
                    }
                )

                let hidden = strip.hiddenTabs(in: strip.viewportFrame)
                if !hidden.isEmpty {
                    showHiddenTabsButton(hidden)
                }
            }
            .frame(height: Islands.tabStripHeight)
        }
    }
}

struct EditorHiddenTabsMenuContent: View {
    let hidden: [CEWorkspaceFile.ID]
    let strip: EditorTabStripModel
    let editor: Editor
    let editorManager: EditorManager

    var body: some View {
        ForEach(hidden, id: \.self) { id in
            Button { strip.reveal(id, in: editor, editorManager: editorManager) } label: {
                if let file = editor.tabs.first(where: { $0.file.id == id })?.file {
                    Label {
                        Text(file.name)
                    } icon: {
                        Image(IntelliJIcon.fileIcon(for: file.name))
                    }
                }
            }
        }
    }
}

nonisolated protocol DragLocated: PointerLocated {
    var startLocation: CGPoint { get }
}

extension DragGesture.Value: DragLocated {}

struct EditorTabDragHandler {
    let id: CEWorkspaceFile.ID
    let strip: EditorTabStripModel
    let editor: Editor

    func changed(_ value: some DragLocated) {
        strip.dragChanged(id: id, startX: value.startLocation.x, currentX: value.location.x)
    }

    func ended(_ value: some DragLocated) {
        strip.dragEnded(editor: editor)
    }
}
