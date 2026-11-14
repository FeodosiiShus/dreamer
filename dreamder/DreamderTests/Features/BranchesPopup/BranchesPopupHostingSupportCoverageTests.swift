import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class BranchesPopupKeySinkView: NSView {
    var received = 0

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        received += event.windowNumber == window?.windowNumber ? 1 : 0
    }
}

@MainActor
private struct BranchesPopupKeyWindow {
    let window: NSWindow

    init(content: NSView) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = content
        window.orderFront(nil)
        window.makeKey()
        window.makeFirstResponder(content)
    }

    func send(_ keyCode: UInt16) throws {
        window.makeKey()
        NSApp.sendEvent(try BranchesPopupCoverageKeys.event(keyCode, in: window))
    }

    func close() {
        window.close()
    }
}

@MainActor
private final class BranchesPopupHandlerRecorder {
    var keyCodes: [UInt16] = []
    var consumes = true
}

@MainActor
private final class BranchesPopupWindowRecorder {
    var windows: [NSWindow?] = []
}

@MainActor
private final class BranchesPopupSizeRecorder {
    var sizes: [CGSize] = []
}

@MainActor
private final class BranchesPopupPopUpRecorder {
    var calls: [(menu: NSMenu, point: NSPoint, view: NSView)] = []
    var blockingFlags: [Bool] = []

    func presentation(model: BranchesPopupViewModel, fallback: NSView?) -> BranchesPopupMenuPresentation {
        BranchesPopupMenuPresentation(
            popUp: { [self] menu, point, view in
                calls.append((menu, point, view))
                blockingFlags.append(model.isBlockingInput)
            },
            fallbackView: { fallback }
        )
    }
}

private func drainMainQueue() async throws {
    try await Task.sleep(for: .milliseconds(100))
}

@MainActor
@Suite(.uiGate)
struct BranchesPopupAnchorsCoverageTests {
    @Test
    func rowAnchorsOnlyReturnViewsAttachedToAWindow() {
        let anchors = BranchesPopupRowAnchors()
        let id = BranchesPopupItemID.ref(.local, "main")
        let detached = NSView(frame: NSRect(x: 0, y: 0, width: 4, height: 4))
        #expect(anchors.view(for: id) == nil)

        anchors.register(detached, for: id)
        #expect(anchors.view(for: id) == nil)

        let hosted = HostedViewFixture.host { Color.clear }
        defer { hosted.close() }
        hosted.rootView.addSubview(detached)
        #expect(anchors.view(for: id) === detached)
        #expect(anchors.view(for: .ref(.local, "other")) == nil)
    }

    @Test
    func rowAnchorViewRegistersAnInteractionTransparentViewAndFollowsIdChanges() async throws {
        let anchors = BranchesPopupRowAnchors()
        let first = BranchesPopupItemID.ref(.local, "first")
        let second = BranchesPopupItemID.ref(.local, "second")
        let hosted = HostedViewFixture.host {
            BranchesPopupAnchorView(id: first, anchors: anchors).frame(width: 20, height: 20)
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(50))

        let view = try #require(anchors.view(for: first))
        #expect(view is BranchesPopupNonInteractiveView)
        #expect(view.hitTest(NSPoint(x: 1, y: 1)) == nil)

        hosted.hosting.rootView = AnyView(BranchesPopupAnchorView(id: second, anchors: anchors).frame(width: 20, height: 20))
        try await eventually { anchors.view(for: second) === view }
    }

    @Test
    func toolbarAnchorTracksTheHostedView() async throws {
        let first = ToolbarPopupAnchor()
        let second = ToolbarPopupAnchor()
        let hosted = HostedViewFixture.host {
            ToolbarPopupAnchorView(anchor: first).frame(width: 10, height: 10)
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(50))

        let view = try #require(first.view)
        #expect(view.window === hosted.window)

        hosted.hosting.rootView = AnyView(ToolbarPopupAnchorView(anchor: second).frame(width: 10, height: 10))
        try await eventually { second.view === view }
    }

    @Test
    func windowReaderReportsTheHostingWindowAndItsRemoval() async throws {
        let first = BranchesPopupWindowRecorder()
        let second = BranchesPopupWindowRecorder()
        let hosted = HostedViewFixture.host {
            BranchesPopupWindowReader { first.windows.append($0) }
        }
        defer { hosted.close() }
        try await eventually { first.windows.contains { $0 === hosted.window } }

        let reader = try #require(hosted.views(of: BranchesPopupWindowReaderView.self).first)
        #expect(reader.hitTest(.zero) == nil)
        reader.onWindowChange = { second.windows.append($0) }
        reader.removeFromSuperview()

        try await eventually { second.windows.contains { $0 == nil } }
    }

    @Test
    func windowReaderUpdatesItsHandlerWhenTheRepresentableChanges() async throws {
        let first = BranchesPopupWindowRecorder()
        let second = BranchesPopupWindowRecorder()
        let hosted = HostedViewFixture.host {
            BranchesPopupWindowReader { first.windows.append($0) }
        }
        defer { hosted.close() }
        try await eventually { first.windows.contains { $0 === hosted.window } }

        hosted.hosting.rootView = AnyView(BranchesPopupWindowReader { second.windows.append($0) })

        try await eventually { second.windows.contains { $0 === hosted.window } }
    }

    @Test
    func sizeReporterReportsInitialAndChangedSizes() async throws {
        let recorder = BranchesPopupSizeRecorder()
        let hosted = HostedViewFixture.host {
            Color.red
                .frame(width: 120, height: 40)
                .modifier(BranchesPopupSizeReporter(onSizeChange: { recorder.sizes.append($0) }))
        }
        defer { hosted.close() }
        try await eventually { recorder.sizes.contains(CGSize(width: 120, height: 40)) }

        hosted.hosting.rootView = AnyView(
            Color.red
                .frame(width: 90, height: 30)
                .modifier(BranchesPopupSizeReporter(onSizeChange: { recorder.sizes.append($0) }))
        )
        try await eventually { recorder.sizes.contains(CGSize(width: 90, height: 30)) }
    }

    @Test
    func sizeReporterWithoutHandlerStillRenders() async throws {
        let hosted = HostedViewFixture.host {
            Color.red
                .frame(width: 120, height: 40)
                .modifier(BranchesPopupSizeReporter(onSizeChange: nil))
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(50))

        #expect(hosted.renders())
    }
}

@MainActor
@Suite(.uiGate)
struct BranchesPopupPanelCoverageTests {
    private func makePanel(center: NotificationCenter = NotificationCenter()) -> BranchesPopupPanel {
        let panel = BranchesPopupPanel(size: NSSize(width: 380, height: 260), notificationCenter: center)
        panel.hidesOnDeactivate = false
        return panel
    }

    @Test
    func panelIsAFloatingKeyablePanelThatCannotBecomeMain() {
        let panel = makePanel()

        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.isFloatingPanel)
        #expect(panel.level == .floating)
        #expect(panel.frame.size == NSSize(width: 380, height: 260))
    }

    @Test
    func resizeKeepsTheTopEdgeAndIgnoresDegenerateOrUnchangedSizes() {
        let panel = makePanel()
        let top = panel.frame.maxY
        let left = panel.frame.minX

        panel.resize(to: CGSize(width: 1, height: 300))
        panel.resize(to: CGSize(width: 300, height: 1))
        panel.resize(to: CGSize(width: 380, height: 260))
        #expect(panel.frame.size == NSSize(width: 380, height: 260))

        panel.resize(to: CGSize(width: 400, height: 320))
        #expect(panel.frame.size == NSSize(width: 400, height: 320))
        #expect(panel.frame.maxY == top)
        #expect(panel.frame.minX == left)
    }

    @Test
    func placeBelowTheAnchorClampsHorizontallyAndFlipsAboveWhenThereIsNoRoom() {
        let gap = Islands.islandGap
        let probe = makePanel()
        guard let visible = probe.screen?.visibleFrame else {
            probe.place(below: NSRect(x: 50, y: 700, width: 100, height: 20))
            #expect(probe.frame.origin == NSPoint(x: 50, y: 700 - 260 - gap))
            return
        }

        let below = makePanel()
        let anchor = NSRect(x: visible.minX + 100, y: visible.maxY - 60, width: 100, height: 20)
        below.place(below: anchor)
        #expect(below.frame.origin == NSPoint(x: anchor.minX, y: anchor.minY - 260 - gap))

        let leftClamped = makePanel()
        leftClamped.place(below: NSRect(x: visible.minX - 400, y: visible.maxY - 60, width: 100, height: 20))
        #expect(leftClamped.frame.minX == visible.minX + 8)

        let rightClamped = makePanel()
        rightClamped.place(below: NSRect(x: visible.maxX + 400, y: visible.maxY - 60, width: 100, height: 20))
        #expect(rightClamped.frame.maxX == visible.maxX - 8)

        let flipped = makePanel()
        let low = NSRect(x: visible.minX + 100, y: visible.minY, width: 100, height: 20)
        flipped.place(below: low)
        #expect(flipped.frame.minY == low.maxY + gap)
    }

    @Test
    func resigningKeyClosesAVisiblePanelButNotAnInvisibleOne() {
        let panel = makePanel()
        var closes = 0
        panel.onClose = { closes += 1 }
        let note = Notification(name: NSWindow.didResignKeyNotification)

        panel.windowDidResignKey(note)
        #expect(closes == 0)

        panel.orderFront(nil)
        #expect(panel.isVisible)
        panel.windowDidResignKey(note)
        #expect(closes == 1)
        #expect(!panel.isVisible)
        #expect(panel.onClose == nil)
    }

    @Test
    func resigningKeyWhileAMenuIsTrackedKeepsThePanelUntilTrackingEnds() async throws {
        let center = NotificationCenter()
        let panel = makePanel(center: center)
        var closes = 0
        panel.onClose = { closes += 1 }
        panel.orderFront(nil)
        #expect(panel.isVisible)

        center.post(name: BranchesPopupMenuTracking.begin, object: nil)
        try await drainMainQueue()
        panel.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        #expect(closes == 0)
        #expect(panel.isVisible)

        center.post(name: BranchesPopupMenuTracking.end, object: nil)
        try await eventually { closes == 1 }
        #expect(!panel.isVisible)
    }

    @Test
    func endOfMenuTrackingLeavesAnInvisiblePanelAlone() async throws {
        let center = NotificationCenter()
        let panel = makePanel(center: center)
        var closes = 0
        panel.onClose = { closes += 1 }

        center.post(name: BranchesPopupMenuTracking.begin, object: nil)
        center.post(name: BranchesPopupMenuTracking.end, object: nil)
        try await drainMainQueue()

        #expect(closes == 0)
    }

    @Test
    func closingDetachesFromTheParentAndNotifiesOnce() {
        let parent = HostedViewFixture.host { Color.clear }
        defer { parent.close() }
        let panel = makePanel()
        var closes = 0
        panel.onClose = { closes += 1 }
        parent.window.addChildWindow(panel, ordered: .above)
        #expect(panel.parent === parent.window)

        panel.close()
        panel.close()

        #expect(closes == 1)
        #expect(panel.parent == nil)
        #expect(parent.window.childWindows?.isEmpty ?? true)
    }
}

@MainActor
@Suite(.uiGate)
struct BranchesPopupPanelHostCoverageTests {
    private func makeWorkspace(in directory: URL, extraBranches: Int = 0) async throws -> WorkspaceDocument {
        let fixture = try await GitMergeFixture(root: directory)
        try fixture.write("a.txt", "a\n")
        try await fixture.commit("initial")
        let sha = try await fixture.run("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        for index in 0..<extraBranches {
            try fixture.write(".git/refs/heads/topic-\(index)", sha + "\n")
        }
        return try HostedViewFixture.makeWorkspace(in: directory)
    }

    private func childPanels(of window: NSWindow) -> [BranchesPopupPanel] {
        (window.childWindows ?? []).compactMap { $0 as? BranchesPopupPanel }
    }

    @Test
    func showWithoutAnAnchorWindowDoesNothing() async throws {
        try await withTempDir { directory in
            let workspace = try await makeWorkspace(in: directory)
            defer { workspace.close() }
            let manager = try #require(workspace.sourceControlManager)
            let bystander = HostedViewFixture.host { Color.clear }
            defer { bystander.close() }

            BranchesPopupPanelHost().show(
                sourceControlManager: manager,
                workspace: workspace,
                anchoredTo: NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
            )

            #expect(childPanels(of: bystander.window).isEmpty)
        }
    }

    @Test
    func showAttachesAPanelAndDismissOrASecondShowClosesIt() async throws {
        try await withTempDir { directory in
            let workspace = try await makeWorkspace(in: directory)
            defer { workspace.close() }
            let manager = try #require(workspace.sourceControlManager)
            let hosted = HostedViewFixture.host(size: NSSize(width: 800, height: 600)) { Color.clear }
            defer {
                childPanels(of: hosted.window).forEach { $0.close() }
                hosted.close()
            }
            let host = BranchesPopupPanelHost()

            host.show(sourceControlManager: manager, workspace: workspace, anchoredTo: hosted.rootView)
            let first = try #require(childPanels(of: hosted.window).first)
            #expect(first.parent === hosted.window)
            #expect(first.contentView is NSHostingView<GitBranchesPopupView>)

            host.show(sourceControlManager: manager, workspace: workspace, anchoredTo: hosted.rootView)
            #expect(first.onClose == nil)
            let second = try #require(childPanels(of: hosted.window).first)
            #expect(second !== first)
            #expect(childPanels(of: hosted.window).count == 1)

            host.dismiss(in: hosted.window)
            #expect(second.onClose == nil)
            #expect(childPanels(of: hosted.window).isEmpty)
        }
    }

    @Test
    func escapeInsideThePopupClosesThePanelThroughTheInstalledKeyMonitor() async throws {
        try await withTempDir { directory in
            let workspace = try await makeWorkspace(in: directory)
            defer { workspace.close() }
            let manager = try #require(workspace.sourceControlManager)
            let hosted = HostedViewFixture.host(size: NSSize(width: 800, height: 600)) { Color.clear }
            defer { hosted.close() }
            let host = BranchesPopupPanelHost()
            host.show(sourceControlManager: manager, workspace: workspace, anchoredTo: hosted.rootView)
            let panel = try #require(childPanels(of: hosted.window).first)

            try await eventually {
                guard panel.onClose != nil else { return true }
                if let escape = BranchesPopupCoverageKeys.optionalEvent(53, in: panel) {
                    NSApp.sendEvent(escape)
                }
                return panel.onClose == nil
            }

            #expect(childPanels(of: hosted.window).isEmpty)
        }
    }

    @Test
    func panelFollowsThePreferredHeightReportedByThePopup() async throws {
        try await withTempDir { directory in
            let workspace = try await makeWorkspace(in: directory, extraBranches: 40)
            defer { workspace.close() }
            let manager = try #require(workspace.sourceControlManager)
            let hosted = HostedViewFixture.host(size: NSSize(width: 800, height: 600)) { Color.clear }
            defer {
                childPanels(of: hosted.window).forEach { $0.close() }
                hosted.close()
            }
            let host = BranchesPopupPanelHost()
            host.show(sourceControlManager: manager, workspace: workspace, anchoredTo: hosted.rootView)
            let panel = try #require(childPanels(of: hosted.window).first)
            #expect(panel.frame.size == NSSize(width: 380, height: 260))

            try await eventually { panel.frame.height == 560 }
            #expect(panel.frame.width == 380)
        }
    }
}

@MainActor
@Suite(.uiGate)
struct BranchesPopupKeyMonitorCoverageTests {
    private func makeMonitor(
        recorder: BranchesPopupHandlerRecorder,
        center: NotificationCenter
    ) -> BranchesPopupKeyMonitor {
        BranchesPopupKeyMonitor(
            handler: { event in
                recorder.keyCodes.append(event.keyCode)
                return recorder.consumes
            },
            notificationCenter: center
        )
    }

    @Test
    func monitorConsumesHandledKeysOnlyInItsWindowAndStopsAfterRemoval() throws {
        let sink = BranchesPopupKeySinkView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
        let otherSink = BranchesPopupKeySinkView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
        let key = BranchesPopupKeyWindow(content: sink)
        let other = BranchesPopupKeyWindow(content: otherSink)
        defer {
            key.close()
            other.close()
        }
        let recorder = BranchesPopupHandlerRecorder()
        let monitor = makeMonitor(recorder: recorder, center: NotificationCenter())
        monitor.install(on: key.window)

        try key.send(11)
        #expect(recorder.keyCodes == [11])
        #expect(sink.received == 0)

        recorder.consumes = false
        try key.send(12)
        #expect(recorder.keyCodes == [11, 12])
        #expect(sink.received == 1)

        try other.send(13)
        #expect(recorder.keyCodes == [11, 12])
        #expect(otherSink.received == 1)

        monitor.remove()
        monitor.remove()
        try key.send(14)
        #expect(recorder.keyCodes == [11, 12])
        #expect(sink.received == 2)
    }

    @Test
    func monitorStaysQuietWhileAMenuIsTracked() async throws {
        let sink = BranchesPopupKeySinkView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
        let key = BranchesPopupKeyWindow(content: sink)
        defer { key.close() }
        let center = NotificationCenter()
        let recorder = BranchesPopupHandlerRecorder()
        let monitor = makeMonitor(recorder: recorder, center: center)
        monitor.install(on: key.window)
        monitor.install(on: key.window)

        center.post(name: BranchesPopupMenuTracking.begin, object: nil)
        try await drainMainQueue()
        try key.send(11)
        #expect(recorder.keyCodes.isEmpty)
        #expect(sink.received == 1)

        center.post(name: BranchesPopupMenuTracking.end, object: nil)
        try await drainMainQueue()
        try key.send(12)
        #expect(recorder.keyCodes == [12])

        center.post(name: BranchesPopupMenuTracking.end, object: nil)
        try await drainMainQueue()
        center.post(name: BranchesPopupMenuTracking.begin, object: nil)
        try await drainMainQueue()
        try key.send(13)
        #expect(recorder.keyCodes == [12])
        #expect(sink.received == 2)

        center.post(name: BranchesPopupMenuTracking.end, object: nil)
        try await drainMainQueue()
    }

    @Test
    func releasingTheMonitorRemovesItsEventHook() async throws {
        let sink = BranchesPopupKeySinkView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
        let key = BranchesPopupKeyWindow(content: sink)
        defer { key.close() }
        let recorder = BranchesPopupHandlerRecorder()
        weak var weakMonitor: BranchesPopupKeyMonitor?
        do {
            let monitor = makeMonitor(recorder: recorder, center: NotificationCenter())
            weakMonitor = monitor
            monitor.install(on: key.window)
            try key.send(11)
            #expect(recorder.keyCodes == [11])
        }

        try await eventually(timeout: .seconds(30)) { weakMonitor == nil }
        try key.send(12)

        #expect(recorder.keyCodes == [11])
    }
}

@MainActor
@Suite(.uiGate)
struct BranchesPopupKeyboardCoverageTests {
    @Test
    func keysDriveSelectionExpansionActivationAndFavorites() async throws {
        try await withTempDir { directory in
            let isolated = try makeIsolatedDefaults()
            defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
            let harness = try await BranchesPopupCoverageHarness.local(
                in: directory,
                defaults: isolated.defaults
            )
            let model = harness.model
            let sink = BranchesPopupKeySinkView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
            let key = BranchesPopupKeyWindow(content: sink)
            let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
            let textKey = BranchesPopupKeyWindow(content: textView)
            defer {
                key.close()
                textKey.close()
            }
            let anchors = BranchesPopupRowAnchors()
            let popUps = BranchesPopupPopUpRecorder()
            let presentation = popUps.presentation(model: model, fallback: key.window.contentView)
            var dismissals = 0

            @MainActor func press(_ keyCode: UInt16, flags: NSEvent.ModifierFlags = [], in window: NSWindow? = nil) throws -> Bool {
                let event = try BranchesPopupCoverageKeys.event(keyCode, flags: flags, in: window ?? key.window)
                return BranchesPopupKeyboard.handle(
                    event,
                    model: model,
                    anchors: anchors,
                    presentation: presentation,
                    dismiss: { dismissals += 1 }
                )
            }

            for flags in [NSEvent.ModifierFlags.command, .option, .control] {
                #expect(try press(53, flags: flags) == false)
            }
            model.isBlockingInput = true
            #expect(try press(53) == false)
            model.isBlockingInput = false
            #expect(dismissals == 0)

            #expect(try press(53))
            #expect(dismissals == 1)

            let selectable = model.rows.filter(\.isSelectable)
            let firstSelectable = try #require(selectable.first)
            let secondSelectable = try #require(selectable.dropFirst().first)
            model.selectedID = firstSelectable.id
            #expect(try press(125))
            #expect(model.selectedID == secondSelectable.id)
            #expect(try press(126))
            #expect(model.selectedID == firstSelectable.id)

            model.selectedID = .section(.local)
            let expanded = model.isExpanded(.section(.local))
            #expect(try press(124))
            #expect(model.isExpanded(.section(.local)) != expanded)
            #expect(try press(123))
            #expect(model.isExpanded(.section(.local)) == expanded)
            #expect(popUps.calls.isEmpty)

            let featureRow = try harness.row(.ref, shortName: "feature")
            model.selectedID = featureRow.id
            #expect(try press(124))
            #expect(popUps.calls.count == 1)
            let firstCall = try #require(popUps.calls.first)
            #expect(firstCall.view === key.window.contentView)
            #expect(firstCall.point == NSPoint(x: 0, y: 80))
            #expect(firstCall.menu.items.map(\.title).contains("Checkout"))
            #expect(popUps.blockingFlags == [true])
            #expect(!model.isBlockingInput)

            let anchorView = NSView(frame: NSRect(x: 0, y: 0, width: 30, height: 10))
            sink.addSubview(anchorView)
            anchors.register(anchorView, for: featureRow.id)
            #expect(try press(124))
            #expect(popUps.calls.count == 2)
            let secondCall = try #require(popUps.calls.dropFirst().first)
            #expect(secondCall.view === anchorView)
            #expect(secondCall.point == NSPoint(x: 32, y: 0))

            #expect(try press(36))
            #expect(try press(76))
            #expect(harness.presentedRows.map(\.id) == [featureRow.id, featureRow.id])

            model.selectedID = .action(.newBranch)
            #expect(try press(36))
            #expect(harness.branchDialogTitles == ["New Branch"])

            model.selectedID = featureRow.id
            let favorite = featureRow.ref?.id ?? ""
            let wasFavorite = model.favorites.contains(favorite)
            #expect(try press(49, in: textKey.window) == false)
            #expect(model.favorites.contains(favorite) == wasFavorite)
            #expect(try press(49))
            #expect(model.favorites.contains(favorite) != wasFavorite)

            #expect(try press(0) == false)
        }
    }
}

@MainActor
@Suite(.uiGate)
struct BranchesPopupMenuPresenterCoverageTests {
    @Test
    func presenterTogglesNonRefRowsAndPopsUpRefMenusAtTheRightPlace() async throws {
        try await withTempDir { directory in
            let isolated = try makeIsolatedDefaults()
            defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
            let harness = try await BranchesPopupCoverageHarness.local(
                in: directory,
                defaults: isolated.defaults
            )
            let model = harness.model
            let anchors = BranchesPopupRowAnchors()
            let popUps = BranchesPopupPopUpRecorder()
            let featureRow = try harness.row(.ref, shortName: "feature")

            let sectionRow = try harness.row(.section)
            let expanded = model.isExpanded(sectionRow.id)
            BranchesPopupMenuPresenter.present(
                row: sectionRow,
                anchors: anchors,
                model: model,
                presentation: popUps.presentation(model: model, fallback: nil)
            )
            #expect(model.isExpanded(sectionRow.id) != expanded)
            #expect(popUps.calls.isEmpty)

            BranchesPopupMenuPresenter.present(
                row: featureRow,
                anchors: anchors,
                model: model,
                presentation: popUps.presentation(model: model, fallback: nil)
            )
            #expect(popUps.calls.isEmpty)
            #expect(!model.isBlockingInput)

            let detached = NSView(frame: NSRect(x: 0, y: 0, width: 5, height: 5))
            anchors.register(detached, for: featureRow.id)
            let small = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 20))
            BranchesPopupMenuPresenter.present(
                row: featureRow,
                anchors: anchors,
                model: model,
                presentation: popUps.presentation(model: model, fallback: small)
            )
            #expect(popUps.calls.count == 1)
            let smallCall = try #require(popUps.calls.first)
            #expect(smallCall.view === small)
            #expect(smallCall.point == NSPoint(x: 0, y: 0))

            let large = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            BranchesPopupMenuPresenter.present(
                row: featureRow,
                anchors: anchors,
                model: model,
                presentation: popUps.presentation(model: model, fallback: large)
            )
            let largeCall = try #require(popUps.calls.dropFirst().first)
            #expect(largeCall.point == NSPoint(x: 420, y: 560))

            let hosted = HostedViewFixture.host { Color.clear }
            defer { hosted.close() }
            let attached = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 10))
            hosted.rootView.addSubview(attached)
            anchors.register(attached, for: featureRow.id)
            BranchesPopupMenuPresenter.present(
                row: featureRow,
                anchors: anchors,
                model: model,
                presentation: popUps.presentation(model: model, fallback: large)
            )
            let attachedCall = try #require(popUps.calls.dropFirst(2).first)
            #expect(attachedCall.view === attached)
            #expect(attachedCall.point == NSPoint(x: 52, y: 0))
            #expect(popUps.blockingFlags == [true, true, true])
            #expect(!model.isBlockingInput)
        }
    }

    @Test
    func liveFallbackViewIsTheKeyOrMainWindowContent() {
        let expected = NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView

        #expect(BranchesPopupMenuPresentation.live.fallbackView() === expected)
    }

    @Test
    func livePopUpIsInterceptedByTheHeadlessHostAndRecorded() {
        let title = "Live PopUp \(UUID().uuidString)"
        let menu = NSMenu(title: title)
        menu.addItem(NSMenuItem(title: "Item", action: nil, keyEquivalent: ""))
        let hosted = HostedViewFixture.host { Color.clear }
        defer { hosted.close() }

        BranchesPopupMenuPresentation.live.popUp(menu, NSPoint(x: 4, y: 4), hosted.rootView)

        #expect(DreamderHeadless.suppressedModals.contains(title))
    }
}
