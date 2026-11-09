import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct StatusBarWidgetStyleTests {
    private let size = NSSize(width: 160, height: 40)

    private func snapshot<Content: View>(@ViewBuilder _ content: () -> Content) async throws -> NSBitmapImageRep? {
        let hosted = HostedViewFixture.host(size: size, content)
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(100))
        return hosted.snapshot()
    }

    @Test
    func metricsFollowTheIslandsStatusBarTheme() {
        #expect(StatusBarWidgetMetrics.horizontalPadding == 4)
        #expect(StatusBarWidgetMetrics.widgetSpacing == 8)
        #expect(StatusBarWidgetMetrics.barPadding == 4)
        #expect(StatusBarWidgetMetrics.hoverHeight == 20)
        #expect(StatusBarWidgetMetrics.iconSize == 16)
        #expect(StatusBarWidgetMetrics.foreground == Color(hex: 0x9FA2A8))
        #expect(StatusBarWidgetMetrics.hoverForeground == Color(hex: 0xD1D3D9))
        #expect(StatusBarWidgetMetrics.foregroundColor(isHovering: false) == StatusBarWidgetMetrics.foreground)
        #expect(StatusBarWidgetMetrics.foregroundColor(isHovering: true) == StatusBarWidgetMetrics.hoverForeground)
    }

    @Test
    func widgetTextBrightensWhileHovered() async throws {
        let idle = try await snapshot { StatusBarWidgetText(text: "UTF-8") }
        let hovered = try await snapshot { StatusBarWidgetText(text: "UTF-8", isHovering: true) }

        #expect(HostedView.pixelsDiffer(idle, hovered))
    }

    @Test
    func widgetChromePaintsTheHoverBackground() async throws {
        let idle = try await snapshot { StatusBarWidgetText(text: "LF").statusBarWidgetChrome(isHovering: false) }
        let hovered = try await snapshot { StatusBarWidgetText(text: "LF").statusBarWidgetChrome(isHovering: true) }
        let disabled = try await snapshot {
            StatusBarWidgetText(text: "LF").statusBarWidgetChrome(isHovering: false).disabled(true)
        }

        #expect(HostedView.pixelsDiffer(idle, hovered))
        #expect(HostedView.pixelsDiffer(idle, disabled))
    }

    @Test
    func widgetButtonsHandOverTheirHoverStateToTheLabel() async throws {
        let idle = try await snapshot {
            StatusBarWidgetButton(
                action: {},
                label: { hovering in
                    StatusBarWidgetText(text: "Reveal", isHovering: hovering)
                }
            )
        }
        let hovered = try await snapshot {
            StatusBarWidgetButton(
                isHovering: true,
                action: {},
                label: { hovering in
                    StatusBarWidgetText(text: "Reveal", isHovering: hovering)
                }
            )
        }
        let detached = StatusBarWidgetButton(action: {}, label: { _ in Text("x") })

        #expect(HostedView.pixelsDiffer(idle, hovered))
        detached.setHovering(true)
        detached.setHovering(false)
    }

    @Test
    func notificationsButtonPaintsTheHoverBackground() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let harness = NotificationsPanelHarness()
            let idle = try HostedViewFixture.hostInWorkspace(workspace, size: size) {
                StatusBarNotificationsButton(notificationManager: harness.manager)
            }
            let hovered = try HostedViewFixture.hostInWorkspace(workspace, size: size) {
                StatusBarNotificationsButton(notificationManager: harness.manager, isHovering: true)
            }
            defer {
                idle.close()
                hovered.close()
            }
            try await idle.settle(.milliseconds(100))
            try await hovered.settle(.milliseconds(100))

            #expect(idle.renders())
            #expect(HostedView.pixelsDiffer(idle.snapshot(), hovered.snapshot()))
        }
    }

    @Test
    func indentSelectorLabelPaintsTheHoverBackground() async throws {
        let idle = try await snapshot { StatusBarIndentSelector().labelContent }
        let hovered = try await snapshot { StatusBarIndentSelector(isHovering: true).labelContent }

        #expect(HostedView.pixelsDiffer(idle, hovered))
    }

    @Test
    func indentSelectorRendersItsMenuButton() async throws {
        let hosted = HostedViewFixture.host(size: size) { StatusBarIndentSelector(isHovering: true) }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(100))

        #expect(hosted.renders())
    }
}
