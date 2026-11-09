//
//  NotificationBannerView.swift
//  Dreamder
//
//  Created by Austin Condiff on 2/10/24.
//

import SwiftUI

struct NotificationBannerView: View {
    @Environment(\.colorScheme)
    private var colorScheme

    let notification: CENotification
    let onDismiss: () -> Void
    let onAction: () -> Void

    @State private var hover: NotificationBannerHover

    init(
        notification: CENotification,
        panel: NotificationPanelViewModel,
        hover: NotificationBannerHover? = nil,
        onDismiss: @escaping () -> Void,
        onAction: @escaping () -> Void
    ) {
        self.notification = notification
        self.onDismiss = onDismiss
        self.onAction = onAction
        _hover = State(initialValue: hover ?? NotificationBannerHover(panel: panel))
    }

    private var showsHoverControls: Bool {
        !notification.isSticky && hover.isHovering
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                switch notification.icon {
                case let .symbol(name, color):
                    FeatureIcon(
                        symbol: name,
                        color: color ?? Color(.systemBlue),
                        size: 26
                    )
                case let .text(text, backgroundColor, textColor):
                    FeatureIcon(
                        text: text,
                        textColor: textColor ?? .primary,
                        color: backgroundColor ?? Color(.systemBlue),
                        size: 26
                    )
                case let .image(image):
                    FeatureIcon(
                        image: image,
                        size: 26
                    )
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(notification.title)
                        .font(.system(size: 12))
                        .fontWeight(.semibold)
                        .padding(.top, -3)
                    Text(notification.description)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .mask(
                    LinearGradient(
                        gradient: Gradient(
                            colors: [
                                .black,
                                .black,
                                !notification.isSticky && hover.isHovering ? .clear : .black,
                                !notification.isSticky && hover.isHovering ? .clear : .black
                            ]
                        ),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            }
            if notification.isSticky {
                HStack(spacing: 8) {
                    Button(action: onDismiss, label: {
                        Text("Dismiss")
                            .frame(maxWidth: .infinity)
                    })
                    .buttonStyle(.secondaryBlur)
                    .controlSize(.small)
                    Button(action: onAction, label: {
                        Text(notification.actionButtonTitle)
                            .frame(maxWidth: .infinity)
                    })
                    .buttonStyle(.secondaryBlur)
                    .controlSize(.small)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .glassPopup()
        .shadow(
            color: Color(.black.withAlphaComponent(colorScheme == .dark ? 0.2 : 0.1)),
            radius: 5,
            x: 0,
            y: 2
        )
        .overlay(alignment: .bottomTrailing) {
            NotificationBannerActionButton(
                isVisible: showsHoverControls,
                title: notification.actionButtonTitle,
                action: onAction
            )
        }
        .overlay(alignment: .topLeading) {
            NotificationBannerDismissButton(isVisible: showsHoverControls, action: onDismiss)
        }
        .frame(width: 300)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing),
            removal: .modifier(
                active: DismissTransition(
                    useOpactityTransition: notification.isBeingDismissed,
                    isIdentity: false
                ),
                identity: DismissTransition(
                    useOpactityTransition: notification.isBeingDismissed,
                    isIdentity: true
                )
            )
        ))
        .onHover(perform: hover.changed)
    }
}

struct NotificationBannerActionButton: View {
    let isVisible: Bool
    let title: String
    let action: () -> Void

    var body: some View {
        if isVisible {
            Button(action: action, label: {
                Text(title)
            })
            .buttonStyle(.secondaryBlur)
            .controlSize(.small)
            .padding(10)
            .transition(.opacity)
        }
    }
}

struct NotificationBannerDismissButton: View {
    let isVisible: Bool
    let action: () -> Void

    var body: some View {
        if isVisible {
            Button(action: action) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.overlay)
            .padding(.top, -5)
            .padding(.leading, -5)
            .transition(.opacity)
        }
    }
}

@Observable
final class NotificationBannerHover {
    private(set) var isHovering = false

    private let panel: NotificationPanelViewModel

    init(panel: NotificationPanelViewModel) {
        self.panel = panel
    }

    func changed(_ hovering: Bool) {
        withAnimation(.easeOut(duration: 0.2)) {
            isHovering = hovering
        }
        panel.hoverChanged(hovering)
    }
}

struct DismissTransition: ViewModifier {
    let useOpactityTransition: Bool
    let isIdentity: Bool

    func body(content: Content) -> some View {
        content
            .opacity(useOpactityTransition && !isIdentity ? 0 : 1)
            .offset(x: !useOpactityTransition && !isIdentity ? 350 : 0)
    }
}

struct NotificationGlassContainer: ViewModifier {
    func body(content: Content) -> some View {
        GlassEffectContainer(spacing: 8) {
            content
        }
    }
}
