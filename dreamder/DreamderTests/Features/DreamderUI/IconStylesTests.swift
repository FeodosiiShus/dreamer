import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class ToggleBox {
    var value = false

    var binding: Binding<Bool> {
        Binding(get: { self.value }, set: { self.value = $0 })
    }
}

@MainActor
@Suite(.uiGate)
struct IconStylesTests {
    private func snapshot(of style: IconButtonStyle) async throws -> NSBitmapImageRep? {
        let hosted = HostedViewFixture.host(size: NSSize(width: 80, height: 60)) {
            Button(action: {}) { Image(systemName: "plus") }
                .buttonStyle(style)
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(50))
        return hosted.snapshot()
    }

    private func snapshot(of style: IconToggleStyle, isOn: Bool) async throws -> NSBitmapImageRep? {
        let hosted = HostedViewFixture.host(size: NSSize(width: 80, height: 60)) {
            Toggle(isOn: .constant(isOn)) { Image(systemName: "bold") }
                .toggleStyle(style)
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(50))
        return hosted.snapshot()
    }

    @Test
    func activeAndInactiveButtonsRenderDifferently() async throws {
        let active = try await snapshot(of: IconButtonStyle(isActive: true))
        let inactive = try await snapshot(of: IconButtonStyle(isActive: false))

        #expect(active != nil)
        #expect(inactive != nil)
        #expect(HostedView.pixelsDiffer(active, inactive))
    }

    @Test
    func missingOptionsFallBackToTheInactiveDefaultFont() async throws {
        let defaults = try await snapshot(of: IconButtonStyle(isActive: nil, font: nil, size: nil))
        let explicit = try await snapshot(
            of: IconButtonStyle(
                isActive: false,
                font: Font.system(size: 14.5, weight: .regular, design: .default),
                width: nil,
                height: nil
            )
        )

        #expect(defaults != nil)
        #expect(HostedView.pixelsDiffer(defaults, explicit) == false)
    }

    @Test
    func factoryOverloadsCarryTheRequestedMetrics() {
        let square: IconButtonStyle = .icon(size: 30)
        #expect(square.width == 30)
        #expect(square.height == 30)
        #expect(square.isActive == false)

        let rectangle: IconButtonStyle = .icon(isActive: true, size: CGSize(width: 40, height: 20))
        #expect(rectangle.width == 40)
        #expect(rectangle.height == 20)
        #expect(rectangle.isActive == true)

        let defaults: IconButtonStyle = .icon
        #expect(defaults.isActive == nil)
        #expect(defaults.font == nil)
        #expect(defaults.width == nil)
        #expect(defaults.height == nil)

        let optionalSize: IconButtonStyle = .icon(size: CGSize?.none)
        #expect(optionalSize.width == nil)
        #expect(optionalSize.height == nil)
    }

    @Test
    func pressedBrightnessFollowsAppearanceAndActivity() {
        typealias Metric = IconButtonStyle.IconButton

        #expect(Metric.brightness(isPressed: false, colorScheme: .dark, isActive: true) == 0)
        #expect(Metric.brightness(isPressed: false, colorScheme: .light, isActive: false) == 0)
        #expect(Metric.brightness(isPressed: true, colorScheme: .dark, isActive: true) == 0.5)
        #expect(Metric.brightness(isPressed: true, colorScheme: .dark, isActive: false) == 0.5)
        #expect(Metric.brightness(isPressed: true, colorScheme: .light, isActive: true) == -0.25)
        #expect(Metric.brightness(isPressed: true, colorScheme: .light, isActive: false) == -0.75)
    }

    @Test
    func toggleActionFlipsTheBindingBothWays() {
        let box = ToggleBox()
        let flip = IconToggleStyle.toggler(box.binding)

        flip()
        #expect(box.value)
        flip()
        #expect(box.value == false)
    }

    @Test
    func onAndOffTogglesRenderDifferently() async throws {
        let style = IconToggleStyle()
        let on = try await snapshot(of: style, isOn: true)
        let off = try await snapshot(of: style, isOn: false)

        #expect(on != nil)
        #expect(off != nil)
        #expect(HostedView.pixelsDiffer(on, off))
    }

    @Test
    func toggleFactoryCarriesFontAndSize() async throws {
        let sized: IconToggleStyle = .icon(size: CGSize(width: 30, height: 20))
        #expect(sized.size == CGSize(width: 30, height: 20))
        #expect(sized.font != nil)

        let defaults: IconToggleStyle = .icon
        #expect(defaults.size == nil)
        #expect(defaults.font == nil)

        let rendered = try await snapshot(of: sized, isOn: true)
        #expect(rendered != nil)
    }
}
