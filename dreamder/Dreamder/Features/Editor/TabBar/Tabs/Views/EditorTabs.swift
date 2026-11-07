//
//  EditorTabs.swift
//  Dreamder
//
//  Created by Austin Condiff on 9/7/23.
//

import SwiftUI

struct EditorTabs: View {
    typealias TabID = CEWorkspaceFile.ID

    @EnvironmentObject private var editor: Editor
    @EnvironmentObject private var editorManager: EditorManager

    @State private var draggingTabId: TabID?

    @State private var draggingStartLocation: CGFloat?

    @State private var draggingLastLocation: CGFloat?

    @State private var openedTabs: [TabID] = []

    @State private var tabWidth: [TabID: CGFloat] = [:]

    @State private var tabLocations: [TabID: CGRect] = [:]

    @State private var tabOffsets: [TabID: CGFloat] = [:]

    @State private var closeButtonGestureActive: Bool = false

    @State private var scrollOffset: CGFloat = 0

    @State private var scrollTrailingOffset: CGFloat? = 0

    @State private var viewportFrame: CGRect = .zero

    private static let tabSpacing: CGFloat = 4

    private func makeTabDragGesture(id: TabID) -> some Gesture {
        return DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged({ value in
                if closeButtonGestureActive {
                    return
                }

                if draggingTabId != id {
                    draggingTabId = id
                    draggingStartLocation = value.startLocation.x
                    draggingLastLocation = value.location.x
                }
                let currentLocation = value.location.x
                guard let startLocation = draggingStartLocation,
                      let currentIndex = openedTabs.firstIndex(of: id),
                      let currentTabWidth = tabWidth[id],
                      let lastLocation = draggingLastLocation
                else { return }
                let dragDifference = currentLocation - lastLocation
                let previousIndex = currentIndex > 0 ? currentIndex - 1 : nil
                let nextIndex = currentIndex < openedTabs.count - 1 ? currentIndex + 1 : nil
                tabOffsets[id] = currentLocation - startLocation
                if previousIndex != nil && dragDifference < 0 {
                    guard let previousTabIndex = previousIndex,
                          let previousTabLocation = tabLocations[openedTabs[previousTabIndex]],
                          let previousTabWidth = tabWidth[openedTabs[previousTabIndex]]
                    else { return }
                    if currentLocation < max(
                        previousTabLocation.maxX - previousTabWidth * 0.1,
                        previousTabLocation.minX + currentTabWidth * 0.9
                    ) {
                        let changing = previousTabWidth + Self.tabSpacing
                        draggingStartLocation = startLocation - changing
                        withAnimation {
                            tabOffsets[id, default: 0] += changing
                            openedTabs.move(
                                fromOffsets: IndexSet(integer: previousTabIndex),
                                toOffset: currentIndex + 1
                            )
                        }
                        return
                    }
                }
                if nextIndex != nil && dragDifference > 0 {
                    guard let nextTabIndex = nextIndex,
                          let nextTabLocation = tabLocations[openedTabs[nextTabIndex]],
                          let nextTabWidth = tabWidth[openedTabs[nextTabIndex]]
                    else { return }
                    if currentLocation > min(
                        nextTabLocation.minX + nextTabWidth * 0.1,
                        nextTabLocation.maxX - currentTabWidth * 0.9
                    ) {
                        let changing = nextTabWidth + Self.tabSpacing
                        draggingStartLocation = startLocation + changing
                        withAnimation {
                            tabOffsets[id, default: 0] -= changing
                            openedTabs.move(
                                fromOffsets: IndexSet(integer: nextTabIndex),
                                toOffset: currentIndex
                            )
                        }
                        return
                    }
                }
                if draggingLastLocation.map({ abs(value.location.x - $0) >= 10 }) ?? true {
                    draggingLastLocation = value.location.x
                }
            })
            .onEnded({ _ in
                draggingStartLocation = nil
                draggingLastLocation = nil
                withAnimation(.easeInOut(duration: 0.25)) {
                    tabOffsets = [:]
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    draggingTabId = nil
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
                    if draggingStartLocation == nil {
                        editor.tabs = .init(openedTabs.compactMap { id in
                            editor.tabs.first { $0.file.id == id }
                        })
                    }
                }
            })
    }

    private func makeTabItemGeometryReader(id: TabID) -> some View {
        GeometryReader { tabItemGeoReader in
            Rectangle()
                .foregroundColor(.clear)
                .onAppear {
                    tabWidth[id] = tabItemGeoReader.size.width
                    tabLocations[id] = tabItemGeoReader.frame(in: .global)
                }
                .onChange(of: tabItemGeoReader.frame(in: .global)) { _, tabCGRect in
                    tabLocations[id] = tabCGRect
                }
                .onChange(of: tabItemGeoReader.size.width) { _, newWidth in
                    tabWidth[id] = newWidth
                }
        }
    }

    private func hiddenTabs(in viewport: CGRect) -> [TabID] {
        EditorTabOverflow.hiddenTabs(openedTabs: openedTabs, frames: tabLocations, viewport: viewport)
    }

    private func revealTab(_ id: TabID, proxy: ScrollViewProxy) {
        guard let tab = editor.tabs.first(where: { $0.file.id == id }) else { return }
        editorManager.activeEditor = editor
        editor.setSelectedTab(tab.file)
        editor.clearFuture()
        editor.addToHistory(tab)
        withAnimation {
            proxy.scrollTo(id, anchor: .trailing)
        }
    }

    private func showHiddenTabsButton(_ hidden: [TabID], proxy: ScrollViewProxy) -> some View {
        Menu {
            ForEach(hidden, id: \.self) { id in
                Button {
                    revealTab(id, proxy: proxy)
                } label: {
                    if let file = editor.tabs.first(where: { $0.file.id == id })?.file {
                        Label {
                            Text(file.name)
                        } icon: {
                            Image(IntelliJIcon.fileIcon(for: file.name))
                        }
                    }
                }
            }
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

    private func synchronizeTabs() {
        openedTabs = editor.tabs.map(\.file.id)
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
                    HStack(spacing: Self.tabSpacing) {
                        ForEach(Array(openedTabs.enumerated()), id: \.element) { index, id in
                            if let item = editor.tabs.first(where: { $0.file.id == id }) {
                                EditorTabView(
                                    file: item.file,
                                    index: index,
                                    draggingTabId: draggingTabId,
                                    closeButtonGestureActive: $closeButtonGestureActive
                                )
                                .fixedSize()
                                .transition(
                                    .asymmetric(
                                        insertion: .offset(x: -14).combined(with: .opacity),
                                        removal: .opacity
                                    )
                                )
                                .background(makeTabItemGeometryReader(id: id))
                                .offset(x: tabOffsets[id] ?? 0, y: 0)
                                .simultaneousGesture(makeTabDragGesture(id: id), including: .all)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .onAppear {
                        synchronizeTabs()
                        scrollReader.scrollTo(editor.selectedTab?.file.id)
                    }
                    .onChange(of: editor.tabs) { tabs, newValue in
                        if tabs.count == newValue.count {
                            synchronizeTabs()
                        } else {
                            withAnimation(.easeOut(duration: 0.20)) {
                                synchronizeTabs()
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
                }
                .background(
                    GeometryReader { viewportProxy in
                        Color.clear
                            .onAppear { viewportFrame = viewportProxy.frame(in: .global) }
                            .onChange(of: viewportProxy.frame(in: .global)) { _, frame in
                                viewportFrame = frame
                            }
                    }
                )

                let hidden = hiddenTabs(in: viewportFrame)
                if !hidden.isEmpty {
                    showHiddenTabsButton(hidden, proxy: scrollReader)
                }
            }
            .frame(height: Islands.tabStripHeight)
        }
    }
}
