import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ToolWindowHeaderTests {
    private func host<Content: View>(@ViewBuilder _ content: () -> Content) async throws -> HostedView {
        let hosted = HostedViewFixture.host(size: NSSize(width: 400, height: 120)) {
            content().background(Color.black)
        }
        try await hosted.settle(.milliseconds(50))
        return hosted
    }

    @Test
    func headerRendersWithDefaultTabsAndActions() async throws {
        let plain = try await host { ToolWindowHeader(title: "Plain") }
        defer { plain.close() }
        let decorated = try await host {
            ToolWindowHeader(title: "Plain") {
                Text("Tab")
            } actions: {
                ToolWindowActionButton(systemImage: "gear", help: "Settings") {}
            }
        }
        defer { decorated.close() }

        #expect(plain.renders())
        #expect(decorated.renders())
        #expect(HostedView.pixelsDiffer(plain.snapshot(), decorated.snapshot()))
    }

    @Test
    func tabRendersIconCloseButtonAndSelectionVariants() async throws {
        let selected = try await host {
            ToolWindowTab(title: "Selected", icon: "toolwindows/project_20", isSelected: true, onClose: {}, action: {})
        }
        defer { selected.close() }
        let unselected = try await host {
            ToolWindowTab(title: "Unselected", isSelected: false, action: {})
        }
        defer { unselected.close() }
        let unselectedClosable = try await host {
            ToolWindowTab(title: "Unselected", isSelected: false, onClose: {}, action: {})
        }
        defer { unselectedClosable.close() }

        #expect(selected.renders())
        #expect(unselected.renders())
        #expect(HostedView.pixelsDiffer(selected.snapshot(), unselected.snapshot()))
        #expect(unselectedClosable.renders())
    }

    @Test
    func actionButtonRendersSystemImageAndBundledIcon() async throws {
        let system = try await host { ToolWindowActionButton(systemImage: "gear", help: "System") {} }
        defer { system.close() }
        let bundled = try await host { ToolWindowActionButton(icon: "general/hide", help: "Bundled") {} }
        defer { bundled.close() }

        #expect(system.renders())
        #expect(bundled.renders())
        #expect(HostedView.pixelsDiffer(system.snapshot(), bundled.snapshot()))
    }

    @Test
    func actionButtonsUseTheDisabledTintWhenDisabled() async throws {
        let enabledIcon = try await host { ToolWindowActionButton(icon: "general/hide", help: "Hide") {} }
        defer { enabledIcon.close() }
        let disabledIcon = try await host {
            ToolWindowActionButton(icon: "general/hide", help: "Hide") {}.disabled(true)
        }
        defer { disabledIcon.close() }
        let enabledSystem = try await host { ToolWindowActionButton(systemImage: "gear", help: "Gear") {} }
        defer { enabledSystem.close() }
        let disabledSystem = try await host {
            ToolWindowActionButton(systemImage: "gear", help: "Gear") {}.disabled(true)
        }
        defer { disabledSystem.close() }

        #expect(HostedView.pixelsDiffer(enabledIcon.snapshot(), disabledIcon.snapshot()))
        #expect(HostedView.pixelsDiffer(enabledSystem.snapshot(), disabledSystem.snapshot()))
    }

    @Test
    func glassSurfacesFollowTheBackgroundImageSetting() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }

        let plain = try await host {
            Text("glass").frame(width: 120, height: 40).glassIsland().defaultAppStorage(defaults)
        }
        defer { plain.close() }
        let popup = try await host {
            Text("popup").frame(width: 120, height: 40).glassPopup().defaultAppStorage(defaults)
        }
        defer { popup.close() }
        let background = try await host {
            Text("island").frame(width: 120, height: 40).island().defaultAppStorage(defaults)
        }
        defer { background.close() }

        defaults.set("/tmp/dreamder-island-background.png", forKey: Islands.BackgroundImageKey.path)
        defaults.set(0.5, forKey: Islands.BackgroundImageKey.opacity)
        let withImage = try await host {
            Text("glass").frame(width: 120, height: 40).glassIsland().defaultAppStorage(defaults)
        }
        defer { withImage.close() }
        let withImagePopup = try await host {
            Text("popup").frame(width: 120, height: 40).glassPopup().defaultAppStorage(defaults)
        }
        defer { withImagePopup.close() }

        #expect(plain.renders())
        #expect(popup.renders())
        #expect(background.renders())
        #expect(withImage.renders())
        #expect(withImagePopup.renders())
    }
}
