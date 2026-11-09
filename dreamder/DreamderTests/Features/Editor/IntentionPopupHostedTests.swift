import AppKit
import SwiftUI
import Testing
@testable import Dreamder

private final class IntentionPopupFocusableView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
@Suite(.serialized, .uiGate)
struct IntentionPopupHostedTests {
    @MainActor
    private struct Harness {
        let workspace: WorkspaceDocument
        let controller: DreamderWindowController
        let window: NSWindow

        func close() {
            for child in window.childWindows ?? [] {
                child.close()
            }
            window.close()
            workspace.close()
        }
    }

    private func makeHarness(in directory: URL) throws -> Harness {
        let workspace = WorkspaceDocument()
        try workspace.read(from: directory, ofType: "")
        workspace.makeWindowControllers()
        let controller = try #require(workspace.windowControllers.first as? DreamderWindowController)
        let window = try #require(controller.window)
        window.isReleasedWhenClosed = false
        window.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
        return Harness(workspace: workspace, controller: controller, window: window)
    }

    private func childPanel(in window: NSWindow) throws -> IntentionPopupPanel {
        try #require(window.childWindows?.compactMap { $0 as? IntentionPopupPanel }.first)
    }

    private func snapshot(of model: IntentionPopupModel, size: NSSize = NSSize(width: 360, height: 220)) async throws -> NSBitmapImageRep? {
        let host = HostedViewFixture.host(size: size) { IntentionPopupView(model: model) }
        defer { host.close() }
        try await host.settle(.milliseconds(60))
        return host.snapshot()
    }

    private func mouseEvent() throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }

    private func hasVisiblePixels(_ representation: NSBitmapImageRep?) -> Bool {
        guard let representation else { return false }
        for y in 0..<representation.pixelsHigh {
            for x in 0..<representation.pixelsWide {
                if let color = representation.colorAt(x: x, y: y), color.alphaComponent > 0.05 {
                    return true
                }
            }
        }
        return false
    }

    @Test
    func viewRendersSectionsSelectionAndMessageVariants() async throws {
        let list = IntentionPopupModel(groups: IntentionPopupFixtures.sampleGroups)
        let first = try await snapshot(of: list)
        list.select(4)
        let second = try await snapshot(of: list)
        let message = try await snapshot(of: IntentionPopupModel(message: "No context actions available"))
        let sourceOnly = try await snapshot(
            of: IntentionPopupModel(groups: [IntentionPopupFixtures.sampleGroups[2]])
        )

        #expect(HostedView.pixelsDiffer(first, second))
        #expect(HostedView.pixelsDiffer(first, message))
        #expect(HostedView.pixelsDiffer(first, sourceOnly))
        #expect(HostedView.pixelsDiffer(message, sourceOnly))
    }

    @Test
    func selectionChangesScrollTheListWithoutBreakingRendering() async throws {
        let many = (0..<30).map { IntentionPopupFixtures.action("Fix \($0)") }
        let model = IntentionPopupModel(groups: [IntentionPopupFixtures.group("Many", actions: many)])
        let host = HostedViewFixture.host(size: NSSize(width: 360, height: 200)) { IntentionPopupView(model: model) }
        defer { host.close() }
        try await host.settle(.milliseconds(60))
        let top = host.snapshot()

        model.select(25)
        try await host.settle(.milliseconds(150))

        #expect(host.renders())
        #expect(HostedView.pixelsDiffer(top, host.snapshot()))
    }

    @Test
    func rowTapAndHoverDriveTheModel() {
        let model = IntentionPopupModel(groups: IntentionPopupFixtures.sampleGroups)
        var applied: [String] = []
        model.onApply = { applied.append($0.title) }
        let target = IntentionPopupFixtures.action("Extract", category: .refactoring)
        let row = IntentionPopupActionView(model: model, action: target, index: 4)

        row.handleHover(false)
        #expect(model.selectedIndex == 1)
        row.handleHover(true)
        #expect(model.selectedIndex == 4)

        model.select(1)
        row.handleTap()
        #expect(model.selectedIndex == 4)
        #expect(applied == ["Extract"])
    }

    @Test
    func returnAppliesTheSelectedActionAndClosesThePanel() async throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            var applied: [String] = []

            IntentionPopupHost.shared.show(
                groups: IntentionPopupFixtures.sampleGroups,
                in: harness.controller,
                anchor: nil
            ) { applied.append($0.title) }

            let panel = try childPanel(in: harness.window)
            let hostingView = try #require(panel.contentView as? NSHostingView<IntentionPopupView>)
            #expect(panel.frame.size.width == IntentionPopupModel.listWidth)
            #expect(hostingView.sizingOptions.isEmpty)

            panel.sendEvent(try IntentionPopupFixtures.keyEvent(125))
            panel.sendEvent(try IntentionPopupFixtures.keyEvent(36))

            #expect(applied == ["Import x"])
            #expect(harness.window.childWindows?.contains { $0 is IntentionPopupPanel } != true)
        }
    }

    @Test
    func escapeClosesWithoutApplyingAndUnhandledKeysFallThrough() async throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            var applied = 0

            IntentionPopupHost.shared.show(
                groups: IntentionPopupFixtures.sampleGroups,
                in: harness.controller,
                anchor: NSRect(x: 100, y: 400, width: 2, height: 16)
            ) { _ in applied += 1 }

            let panel = try childPanel(in: harness.window)
            panel.sendEvent(try IntentionPopupFixtures.keyEvent(0))
            #expect(harness.window.childWindows?.contains { $0 is IntentionPopupPanel } == true)

            panel.sendEvent(try IntentionPopupFixtures.keyEvent(53))

            #expect(applied == 0)
            #expect(harness.window.childWindows?.contains { $0 is IntentionPopupPanel } != true)
        }
    }

    @Test
    func showingAgainReplacesThePreviousPanelAndMessagesAreSupported() async throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }

            IntentionPopupHost.shared.show(
                groups: IntentionPopupFixtures.sampleGroups,
                in: harness.controller,
                anchor: nil
            ) { _ in }
            let first = try childPanel(in: harness.window)

            IntentionPopupHost.shared.showMessage("Nothing to do", in: harness.controller)

            let panels = harness.window.childWindows?.compactMap { $0 as? IntentionPopupPanel } ?? []
            #expect(panels.count == 1)
            #expect(panels.first !== first)
            let message = try #require(panels.first)
            #expect(message.frame.size.width == IntentionPopupModel.messageWidth)
            #expect(message.frame.size.height == IntentionPopupModel.messageHeight)
            message.sendEvent(try IntentionPopupFixtures.keyEvent(36))
            #expect(harness.window.childWindows?.contains { $0 is IntentionPopupPanel } == true)
        }
    }

    @Test
    func resigningKeyClosesThePanelAndRestoresTheFirstResponder() async throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let responder = IntentionPopupFocusableView()
            harness.window.contentView?.addSubview(responder)
            _ = harness.window.makeFirstResponder(responder)

            IntentionPopupHost.shared.show(
                groups: IntentionPopupFixtures.sampleGroups,
                in: harness.controller,
                anchor: nil
            ) { _ in }
            let panel = try childPanel(in: harness.window)
            _ = harness.window.makeFirstResponder(nil)

            panel.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))

            #expect(harness.window.childWindows?.contains { $0 is IntentionPopupPanel } != true)
            #expect(harness.window.firstResponder === responder)
            #expect(panel.canBecomeKey)
            #expect(!panel.canBecomeMain)
        }
    }

    @Test
    func bulbViewIsFrameManagedHiddenAndFixedSize() throws {
        let bulb = IntentionPopupBulbView(frame: NSRect(x: 5, y: 7, width: 50, height: 50))

        #expect(bulb.isHidden)
        #expect(!bulb.translatesAutoresizingMaskIntoConstraints)
        #expect(bulb.constraints.isEmpty)
        #expect(bulb.frame == NSRect(origin: NSPoint(x: 5, y: 7), size: IntentionPopupBulbView.size))
        #expect(bulb.acceptsFirstMouse(for: nil))
        #expect(IntelliJIcon.nsImage(IntentionPopupBulbView.iconName) != nil)
        let archived = try NSKeyedArchiver.archivedData(withRootObject: "bulb", requiringSecureCoding: false)
        let coder = try NSKeyedUnarchiver(forReadingFrom: archived)
        #expect(IntentionPopupBulbView(coder: coder) == nil)
    }

    @Test
    func bulbViewMouseDownActivatesAndHoverRepaints() throws {
        let bulb = IntentionPopupBulbView(frame: .zero)
        bulb.isHidden = false
        var activations = 0
        bulb.onActivate = { activations += 1 }

        bulb.mouseDown(with: try mouseEvent())
        #expect(activations == 1)

        func paint() -> NSBitmapImageRep? {
            guard let representation = bulb.bitmapImageRepForCachingDisplay(in: bulb.bounds) else { return nil }
            bulb.cacheDisplay(in: bulb.bounds, to: representation)
            return representation
        }
        let resting = paint()
        #expect(hasVisiblePixels(resting))

        bulb.mouseEntered(with: try mouseEvent())
        let hovered = paint()
        #expect(HostedView.pixelsDiffer(resting, hovered))

        bulb.mouseExited(with: try mouseEvent())
        #expect(!HostedView.pixelsDiffer(resting, paint()))
    }

    @Test
    func bulbViewKeepsASingleTrackingAreaAndReceivesHitTests() async throws {
        let host = HostedViewFixture.host(size: NSSize(width: 100, height: 100)) { Color.clear }
        defer { host.close() }
        let bulb = IntentionPopupBulbView(frame: NSRect(x: 10, y: 10, width: 16, height: 16))
        bulb.isHidden = false
        host.hosting.addSubview(bulb)

        bulb.updateTrackingAreas()
        bulb.updateTrackingAreas()

        #expect(bulb.trackingAreas.count == 1)
        #expect(bulb.hitTest(NSPoint(x: bulb.frame.midX, y: bulb.frame.midY)) === bulb)
    }
}
