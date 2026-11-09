import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct ActionButtonStyleTests {
    private let size = NSSize(width: 70, height: 50)

    private func snapshot(
        look: ActionButtonLook = .standard,
        isHovering: Bool,
        isPressed: Bool,
        isSelected: Bool = false,
        isEnabled: Bool = true
    ) async throws -> NSBitmapImageRep? {
        let hosted = HostedViewFixture.host(size: size) {
            ActionButtonChrome(look: look, isHovering: isHovering, isPressed: isPressed, isSelected: isSelected) {
                Text("A").frame(width: 30, height: 30)
            }
            .disabled(!isEnabled)
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(100))
        return hosted.snapshot()
    }

    private func stripeSnapshot(
        isHovering: Bool = false,
        isSelected: Bool = false,
        isEnabled: Bool = true
    ) async throws -> NSBitmapImageRep? {
        let hosted = HostedViewFixture.host(size: NSSize(width: 120, height: 80)) {
            Button {
            } label: {
                Color.clear.frame(width: 16, height: 16)
            }
            .buttonStyle(.actionButton(look: .toolWindowStripe, isHovering: isHovering, isSelected: isSelected))
            .disabled(!isEnabled)
            .frame(width: 120, height: 80)
            .background(Color.black)
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(50))
        return hosted.snapshot()
    }

    @Test
    func stateFollowsIntelliJActionButtonLook() {
        #expect(ActionButtonState.resolve(isEnabled: false, isPressed: true, isHovering: true) == .disabled)
        #expect(ActionButtonState.resolve(isEnabled: true, isPressed: true, isHovering: true) == .pressed)
        #expect(ActionButtonState.resolve(isEnabled: true, isPressed: true, isHovering: false) == .pressed)
        #expect(ActionButtonState.resolve(isEnabled: true, isPressed: false, isHovering: true) == .hovered)
        #expect(ActionButtonState.resolve(isEnabled: true, isPressed: false, isHovering: false) == .normal)
    }

    @Test
    func selectionWinsOverHoverAndPressButNeverOverDisabled() {
        for isHovering in [false, true] {
            for isPressed in [false, true] {
                let enabled = ActionButtonState.resolve(
                    isEnabled: true,
                    isPressed: isPressed,
                    isHovering: isHovering,
                    isSelected: true
                )
                let disabled = ActionButtonState.resolve(
                    isEnabled: false,
                    isPressed: isPressed,
                    isHovering: isHovering,
                    isSelected: true
                )

                #expect(enabled == .selected)
                #expect(disabled == .disabled)
            }
        }
    }

    @Test
    func selectedFillDefaultsToThePressedBackgroundAndStripesUseTheAccent() {
        #expect(ActionButtonLook.standard.fills(for: .selected) == [Islands.actionPressed])
        #expect(ActionButtonLook.toolWindowStripe.fills(for: .selected) == [Islands.stripeSelected])
        #expect(ActionButtonLook.toolWindowStripe.fills(for: .hovered) == [Islands.actionHover])
        #expect(ActionButtonLook.toolWindowStripe.fills(for: .pressed) == [Islands.actionPressed])
        #expect(ActionButtonLook.toolWindowStripe.fills(for: .normal).isEmpty)
        #expect(ActionButtonLook.toolWindowStripe.fills(for: .disabled).isEmpty)
    }

    @Test
    func toolWindowLooksCarryTheirIslandsMetrics() {
        let action = ActionButtonLook.toolWindowAction
        let stripe = ActionButtonLook.toolWindowStripe

        #expect(action.size == CGSize(width: Islands.actionButtonSize, height: Islands.actionButtonSize))
        #expect(action.cornerRadius == Islands.actionButtonRadius)
        #expect(action.insets == EdgeInsets())
        #expect(action.opacity(for: .disabled) == 1)
        #expect(stripe.size == CGSize(width: Islands.stripeButtonWidth, height: Islands.stripeButtonHeight))
        #expect(stripe.cornerRadius == Islands.stripeButtonRadius)
        #expect(stripe.insets == Islands.stripeButtonInsets)
        #expect(stripe.opacity(for: .disabled) == 1)
        #expect(ActionButtonLook.standard.size == nil)
    }

    @Test
    func backgroundsUseTheIslandsToolbarTokens() {
        let look = ActionButtonLook.standard

        #expect(look.fills(for: .normal).isEmpty)
        #expect(look.fills(for: .disabled).isEmpty)
        #expect(look.fills(for: .hovered) == [Color.white.opacity(0x17 / 255)])
        #expect(look.fills(for: .pressed) == [Color.white.opacity(0x29 / 255)])
    }

    @Test
    func accentedButtonsPaintTheirColourAndShadeItOnHoverAndPress() {
        let look = ActionButtonLook.mainToolbarButton.accented(.run)

        #expect(look.fills(for: .disabled).isEmpty)
        #expect(look.fills(for: .normal) == [Color(hex: 0x338555)])
        #expect(look.fills(for: .hovered) == [Color(hex: 0x338555), Color.black.opacity(0x19 / 255)])
        #expect(look.fills(for: .pressed) == [Color(hex: 0x338555), Color.black.opacity(0x28 / 255)])
        #expect(ActionButtonLook.standard.accented(.stop).fills(for: .normal) == [Color(hex: 0xC54E58)])
        #expect(look.accented(nil).fills(for: .normal).isEmpty)
        #expect(ActionButtonAccent.iconOverAccent == Color.white)
    }

    @Test
    func disabledButtonsAreDimmed() {
        #expect(ActionButtonLook.standard.opacity(for: .disabled) == 0.4)
        #expect(ActionButtonLook.standard.opacity(for: .normal) == 1)
        #expect(ActionButtonLook.standard.opacity(for: .hovered) == 1)
        #expect(ActionButtonLook.standard.opacity(for: .pressed) == 1)
        #expect(ActionButtonLook.standard.opacity(for: .selected) == 1)
    }

    @Test
    func cornerRadiiAreHalfTheIntelliJArcs() {
        #expect(ActionButtonLook.standard.arc == 8)
        #expect(ActionButtonLook.standard.cornerRadius == 4)
        #expect(ActionButtonLook.mainToolbarDropdown.arc == 12)
        #expect(ActionButtonLook.mainToolbarDropdown.cornerRadius == 6)
        #expect(ActionButtonLook.mainToolbarButton.arc == (Islands.isCompact ? 8 : 12))
        #expect(ActionButtonLook.mainToolbarButton.cornerRadius == (Islands.isCompact ? 4 : 6))
        #expect(ActionButtonLook.statusBarWidget.arc == 4)
        #expect(ActionButtonLook.statusBarWidget.cornerRadius == 2)
    }

    @Test
    func statusBarWidgetsUseTheHoverBackgroundWhilePressed() {
        let look = ActionButtonLook.statusBarWidget

        #expect(look.fills(for: .hovered) == look.fills(for: .pressed))
        #expect(look.fills(for: .hovered) == [Islands.actionHover])
    }

    @Test
    func everyStateRendersDistinctly() async throws {
        let normal = try await snapshot(isHovering: false, isPressed: false)
        let hovered = try await snapshot(isHovering: true, isPressed: false)
        let pressed = try await snapshot(isHovering: true, isPressed: true)
        let disabled = try await snapshot(isHovering: false, isPressed: false, isEnabled: false)
        let accented = try await snapshot(
            look: ActionButtonLook.standard.accented(.run),
            isHovering: false,
            isPressed: false
        )

        #expect(HostedView.pixelsDiffer(normal, hovered))
        #expect(HostedView.pixelsDiffer(hovered, pressed))
        #expect(HostedView.pixelsDiffer(normal, disabled))
        #expect(HostedView.pixelsDiffer(normal, accented))
    }

    @Test
    func theButtonStyleWrapsTheLabelInTheChrome() async throws {
        let renders = HostedViewFixture.host(size: size) {
            Button(
                action: {},
                label: { Text("A").frame(width: 30, height: 30) }
            )
            .buttonStyle(.actionButton(isHovering: true))
        }
        let idle = HostedViewFixture.host(size: size) {
            Button(
                action: {},
                label: { Text("A").frame(width: 30, height: 30) }
            )
            .buttonStyle(ActionButtonStyle())
        }
        defer {
            renders.close()
            idle.close()
        }
        try await renders.settle(.milliseconds(100))
        try await idle.settle(.milliseconds(100))

        #expect(renders.renders())
        #expect(idle.renders())
        #expect(HostedView.pixelsDiffer(renders.snapshot(), idle.snapshot()))
        #expect(ActionButtonStyle().look == .standard)
        #expect(!ActionButtonStyle().isHovering)
    }

    @Test
    func sizedLooksDrawHoverAndSelectionBackgroundsAndNothingWhenDisabled() async throws {
        let idle = try await stripeSnapshot()
        let hover = try await stripeSnapshot(isHovering: true)
        let selected = try await stripeSnapshot(isSelected: true)
        let disabled = try await stripeSnapshot(isHovering: true, isEnabled: false)
        let disabledSelected = try await stripeSnapshot(isSelected: true, isEnabled: false)

        #expect(HostedView.pixelsDiffer(idle, hover))
        #expect(HostedView.pixelsDiffer(idle, selected))
        #expect(HostedView.pixelsDiffer(hover, selected))
        #expect(!HostedView.pixelsDiffer(idle, disabled))
        #expect(!HostedView.pixelsDiffer(idle, disabledSelected))
    }

    @Test
    func selectedChromeUsesThePressedFillUnlessTheLookOverridesIt() async throws {
        let pressed = try await snapshot(isHovering: false, isPressed: true)
        let selected = try await snapshot(isHovering: false, isPressed: false, isSelected: true)

        #expect(!HostedView.pixelsDiffer(pressed, selected))
        let stripeSelected = try await snapshot(
            look: .toolWindowStripe,
            isHovering: false,
            isPressed: false,
            isSelected: true
        )
        #expect(HostedView.pixelsDiffer(selected, stripeSelected))
    }
}
