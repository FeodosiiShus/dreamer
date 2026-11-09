//
//  NotificationPanelView.swift
//  Dreamder
//
//  Created by Austin Condiff on 2/10/24.
//

import SwiftUI

struct NotificationPanelView: View {
    @Environment(WorkspaceDocument.self) private var workspace
    @Environment(\.controlActiveState)
    private var controlActiveState

    private static let scrollResetDelay: Duration = .milliseconds(300)

    @FocusState private var isFocused: Bool

    // ID for the top anchor
    private let topID = "top"

    // Fixed width for notifications
    private let notificationWidth: CGFloat = 320 // 300 + 10 padding on each side

    @ViewBuilder var notifications: some View {
        let visibleNotifications = workspace.notificationPanel.activeNotifications.filter {
            workspace.notificationPanel.isNotificationVisible($0)
        }

        VStack(spacing: 8) {
            ForEach(visibleNotifications, id: \.id) { notification in
                NotificationBannerView(
                    notification: notification,
                    panel: workspace.notificationPanel,
                    onDismiss: workspace.notificationPanel.dismissHandler(for: notification),
                    onAction: workspace.notificationPanel.actionHandler(for: notification)
                )
            }
        }
        .modifier(NotificationGlassContainer())
        .padding(10)
        .animation(.easeInOut(duration: 0.3), value: visibleNotifications)
    }

    @ViewBuilder var notificationsWithScrollView: some View {
        GeometryReader { geometry in
            HStack {
                Spacer()
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .trailing, spacing: 0) {
                            Color.clear
                                .frame(height: 0)
                                .id(topID)
                                .background(
                                    GeometryReader {
                                        Color.clear.preference(
                                            key: ViewOffsetKey.self,
                                            value: -$0.frame(in: .named("scroll")).origin.y
                                        )
                                    }
                                )
                                .onPreferenceChange(
                                    ViewOffsetKey.self,
                                    perform: workspace.notificationPanel.updateScrollOffset
                                )
                            notifications
                        }
                        .background(
                            GeometryReader { proxy in
                                Color.clear.onChange(of: proxy.size.height, initial: true) { _, newValue in
                                    workspace.notificationPanel.contentHeightChanged(
                                        newValue,
                                        containerHeight: geometry.size.height
                                    )
                                }
                            }
                        )
                    }
                    .frame(maxWidth: notificationWidth, alignment: .trailing)
                    .frame(height: min(geometry.size.height, workspace.notificationPanel.contentHeight))
                    .scrollDisabled(!workspace.notificationPanel.hasOverflow)
                    .coordinateSpace(name: "scroll")
                    .onChange(of: isFocused, workspace.notificationPanel.focusChanged)
                    .onChange(of: geometry.size.height, initial: true) { _, newValue in
                        workspace.notificationPanel.containerHeightChanged(newValue)
                    }
                    .task(id: workspace.notificationPanel.isPresented) {
                        await scrollToTopAfterClosing(proxy)
                    }
                    .allowsHitTesting(
                        workspace.notificationPanel.activeNotifications
                            .contains { workspace.notificationPanel.isNotificationVisible($0) }
                    )
                }
            }
        }
    }

    private func scrollToTopAfterClosing(_ proxy: ScrollViewProxy) async {
        let panel = workspace.notificationPanel
        guard !panel.isPresented && !panel.scrolledToTop else { return }
        try? await Task.sleep(for: Self.scrollResetDelay)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            proxy.scrollTo(topID, anchor: .top)
        }
    }

    var body: some View {
        notificationsWithScrollView
            .scrollClipDisabled(true)
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .onChange(of: workspace.notificationPanel.isPresented) { _, isPresented in
                if isPresented {
                    isFocused = true
                }
            }
            .onChange(of: controlActiveState) { _, newState in
                workspace.notificationPanel.controlStateChanged(isActive: newState == .active || newState == .key)
            }
            .opacity(controlActiveState == .active || controlActiveState == .key ? 1 : 0)
            .offset(
                x: (controlActiveState == .active || controlActiveState == .key) &&
                    (workspace.notificationPanel.isPresented || workspace.notificationPanel.scrolledToTop)
                    ? 0
                    : 350
            )
            .animation(.easeInOut(duration: 0.3), value: workspace.notificationPanel.isPresented)
            .animation(.easeInOut(duration: 0.3), value: workspace.notificationPanel.scrolledToTop)
            .animation(.easeInOut(duration: 0.2), value: controlActiveState)
    }
}
