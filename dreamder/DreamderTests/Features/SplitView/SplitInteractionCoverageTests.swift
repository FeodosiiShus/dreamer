import AppKit
import Observation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class SplitCoverageNudges {
    var nudges: [CGFloat] = []
    var drags: [CGFloat] = []
    var ends = 0
    var equalizes = 0
}

@MainActor
@Observable
private final class SplitCoverageWeights {
    var weights: [CGFloat]

    init(_ weights: [CGFloat]) {
        self.weights = weights
    }
}

private struct SplitCoverageHoldingHarness: View {
    @Bindable var model: SplitCoverageWeights

    var body: some View {
        SplitView(axis: .horizontal, weights: $model.weights) {
            Color.red.holdingPriority(NSLayoutConstraint.Priority(300))
            Color.blue
        }
    }
}

private struct SplitCoverageExtraDividers: View {
    var body: some View {
        SplitLayout(
            axis: .horizontal,
            dividerThickness: 1,
            hitThickness: 7,
            weights: [1],
            probe: SplitLayoutProbe()
        ) {
            Color.red
            Color.blue.layoutValue(key: SplitLayoutRoleKey.self, value: .divider)
            Color.green.layoutValue(key: SplitLayoutRoleKey.self, value: .divider)
        }
    }
}

@MainActor
@Suite(.uiGate)
struct SplitInteractionCoverageTests {
    private func makeDivider(axis: Axis, recorder: SplitCoverageNudges) -> SplitDivider {
        SplitDivider(
            axis: axis,
            style: .system(.thin),
            onDrag: { recorder.drags.append($0) },
            onDragEnd: { recorder.ends += 1 },
            onNudge: { recorder.nudges.append($0) },
            onEqualize: { recorder.equalizes += 1 }
        )
    }

    @Test
    func horizontalDividerHandlesLeftAndRightArrows() {
        let recorder = SplitCoverageNudges()
        let divider = makeDivider(axis: .horizontal, recorder: recorder)

        #expect(divider.handleKey(.leftArrow, []) == .handled)
        #expect(divider.handleKey(.rightArrow, []) == .handled)
        #expect(divider.handleKey(.leftArrow, .shift) == .handled)
        #expect(divider.handleKey(.rightArrow, .shift) == .handled)
        #expect(divider.handleKey(.upArrow, []) == .ignored)
        #expect(divider.handleKey(.downArrow, []) == .ignored)
        #expect(recorder.nudges == [-10, 10, -50, 50])
    }

    @Test
    func verticalDividerHandlesUpAndDownArrows() {
        let recorder = SplitCoverageNudges()
        let divider = makeDivider(axis: .vertical, recorder: recorder)

        #expect(divider.handleKey(.upArrow, []) == .handled)
        #expect(divider.handleKey(.downArrow, []) == .handled)
        #expect(divider.handleKey(.upArrow, .shift) == .handled)
        #expect(divider.handleKey(.downArrow, .shift) == .handled)
        #expect(divider.handleKey(.leftArrow, []) == .ignored)
        #expect(divider.handleKey(.rightArrow, []) == .ignored)
        #expect(recorder.nudges == [-10, 10, -50, 50])
    }

    @Test
    func accessibilityAdjustmentsNudgeByOneStep() {
        let recorder = SplitCoverageNudges()
        let divider = makeDivider(axis: .horizontal, recorder: recorder)

        divider.adjust(.increment)
        divider.adjust(.decrement)

        #expect(recorder.nudges == [10, -10])
        #expect(SplitDivider.adjustmentDelta(.increment) == 10)
        #expect(SplitDivider.adjustmentDelta(.decrement) == -10)
    }

    @Test
    func dividersRenderInBothAxes() async throws {
        let recorder = SplitCoverageNudges()
        let row = HostedViewFixture.host(size: NSSize(width: 40, height: 80)) {
            makeDivider(axis: .horizontal, recorder: recorder)
        }
        let column = HostedViewFixture.host(size: NSSize(width: 80, height: 40)) {
            makeDivider(axis: .vertical, recorder: recorder)
        }
        defer {
            row.close()
            column.close()
        }
        try await row.settle()
        try await column.settle()

        #expect(row.renders())
        #expect(column.renders())
    }

    @Test
    func coordinatorKeepsTheDragOriginUntilTheDragEnds() {
        var coordinator = SplitPaneCoordinator()
        let panes = [SplitLayoutPane(weight: 0.5), SplitLayoutPane(weight: 0.5)]
        coordinator.probe.record(panes: panes, lengths: [100, 100])

        let first = coordinator.dragged(pair: 0, translation: 20)
        #expect(abs(first[0] - 0.6) < 1e-9)
        #expect(abs(first[1] - 0.4) < 1e-9)

        coordinator.probe.record(panes: panes, lengths: [999, 1])
        let second = coordinator.dragged(pair: 0, translation: 40)
        #expect(abs(second[0] - 0.7) < 1e-9)
        #expect(abs(second[1] - 0.3) < 1e-9)

        coordinator.endDrag()
        let third = coordinator.dragged(pair: 0, translation: 40)
        #expect(abs(third[0] - 1) < 1e-9)
        #expect(abs(third[1]) < 1e-9)
    }

    @Test
    func coordinatorNudgesFromTheLatestLengths() {
        let coordinator = SplitPaneCoordinator()
        coordinator.probe.record(
            panes: [SplitLayoutPane(weight: 0.5), SplitLayoutPane(weight: 0.5)],
            lengths: [100, 100]
        )

        let weights = coordinator.nudged(pair: 0, delta: -30)

        #expect(abs(weights[0] - 0.35) < 1e-9)
        #expect(abs(weights[1] - 0.65) < 1e-9)
    }

    @Test
    func coordinatorResizesByHoldingPriority() {
        let coordinator = SplitPaneCoordinator()
        coordinator.probe.record(
            panes: [SplitLayoutPane(weight: 0.5, holdingPriority: 300), SplitLayoutPane(weight: 0.5)],
            lengths: [100, 100]
        )

        let resized = coordinator.resized(from: 201, to: 401, dividerThickness: 1)

        #expect(resized?.count == 2)
        #expect(abs((resized?[0] ?? 0) - 0.25) < 1e-9)
        #expect(abs((resized?[1] ?? 0) - 0.75) < 1e-9)
    }

    @Test
    func coordinatorIgnoresDegenerateResizes() {
        let coordinator = SplitPaneCoordinator()
        coordinator.probe.record(
            panes: [SplitLayoutPane(weight: 0.5, holdingPriority: 300), SplitLayoutPane(weight: 0.5)],
            lengths: [100, 100]
        )

        #expect(coordinator.resized(from: 0, to: 401, dividerThickness: 1) == nil)
        #expect(coordinator.resized(from: 201, to: 0, dividerThickness: 1) == nil)
        #expect(coordinator.resized(from: 201, to: 201, dividerThickness: 1) == nil)

        let samePriorities = SplitPaneCoordinator()
        samePriorities.probe.record(
            panes: [SplitLayoutPane(weight: 0.5), SplitLayoutPane(weight: 0.5)],
            lengths: [100, 100]
        )
        #expect(samePriorities.resized(from: 201, to: 401, dividerThickness: 1) == nil)
    }

    @Test
    func coordinatorComparesWeightsWithinTolerance() {
        #expect(SplitPaneCoordinator.isUnchanged([0.5, 0.5], [0.5, 0.5]))
        let nearlyEqual = SplitPaneCoordinator.isUnchanged([0.5, 0.5], [0.5 + 1e-12, 0.5 - 1e-12])
        #expect(nearlyEqual)
        #expect(!SplitPaneCoordinator.isUnchanged([0.5, 0.5], [0.6, 0.4]))
        #expect(!SplitPaneCoordinator.isUnchanged([0.5, 0.5], [1]))
    }

    @Test
    func resizingTheContainerKeepsHigherHoldingPriorityPaneLength() async throws {
        let model = SplitCoverageWeights([0.5, 0.5])
        let hosted = HostedViewFixture.host(size: NSSize(width: 401, height: 200)) {
            SplitCoverageHoldingHarness(model: model)
        }
        defer { hosted.close() }
        try await hosted.settle()

        hosted.window.setContentSize(NSSize(width: 601, height: 200))
        try await hosted.settle()

        #expect(model.weights[0] < 0.4)
        #expect(model.weights[0] > 0.25)
    }

    @Test
    func extraDividersAreParkedAtTheOrigin() async throws {
        let hosted = HostedViewFixture.host(size: NSSize(width: 200, height: 100)) {
            SplitCoverageExtraDividers()
        }
        defer { hosted.close() }

        try await hosted.settle()

        #expect(hosted.renders())
    }

    @Test
    func holdingPriorityModifierStoresTheRawPriority() async throws {
        let model = SplitCoverageWeights([0.5, 0.5])
        let hosted = HostedViewFixture.host(size: NSSize(width: 301, height: 100)) {
            SplitCoverageHoldingHarness(model: model)
        }
        defer { hosted.close() }

        try await hosted.settle()

        #expect(hosted.renders())
    }

    @Test
    func lightAndDarkEditorDividerColorsDiffer() async throws {
        let light = HostedViewFixture.host(size: NSSize(width: 40, height: 40)) {
            Rectangle().fill(DreamderDividerStyle.editorDivider.color)
        }
        let dark = HostedViewFixture.host(size: NSSize(width: 40, height: 40)) {
            Rectangle().fill(DreamderDividerStyle.editorDivider.color)
        }
        defer {
            light.close()
            dark.close()
        }
        light.window.appearance = NSAppearance(named: .aqua)
        dark.window.appearance = NSAppearance(named: .darkAqua)
        try await light.settle()
        try await dark.settle()

        #expect(HostedView.pixelsDiffer(light.snapshot(), dark.snapshot()))
    }

    @Test
    func environmentValuesStoreEdgeInsetsAndSplitEditorHandlers() {
        var values = EnvironmentValues()
        let insets = EdgeInsets(top: 4, leading: 3, bottom: 2, trailing: 1)
        values.edgeInsets = insets
        #expect(values.edgeInsets == insets)
        #expect(EnvironmentValues().edgeInsets == EdgeInsets(top: 1, leading: 0, bottom: 0, trailing: 0))

        EnvironmentValues().splitEditor(.top, Editor())

        var received: [Edge] = []
        values.splitEditor = { edge, _ in received.append(edge) }
        values.splitEditor(.trailing, Editor())
        #expect(received == [.trailing])
    }

    @Test
    func closingAnEditorSkipsNestedLayouts() {
        let nested = Editor()
        let target = Editor()
        let data = SplitViewData(.horizontal, editorLayouts: [
            .vertical(SplitViewData(.vertical, editorLayouts: [.one(nested)])),
            .one(target)
        ])

        data.closeEditor(with: target.id)

        #expect(data.editorLayouts.count == 1)
        #expect(data.indexOfEditor(target) == nil)
    }

    @Test
    func indexOfEditorSkipsNestedLayouts() {
        let inner = Editor()
        let target = Editor()
        let data = SplitViewData(.horizontal, editorLayouts: [
            .vertical(SplitViewData(.vertical, editorLayouts: [.one(inner)])),
            .one(target)
        ])

        #expect(data.indexOfEditor(target) == 1)
        #expect(data.indexOfEditor(inner) == nil)
    }

    @Test
    func replaceChildFindsNestedTargets() {
        let leaf = SplitViewData(.vertical, editorLayouts: [.one(Editor())])
        let middle = SplitViewData(.horizontal, editorLayouts: [.vertical(leaf)])
        let root = SplitViewData(.vertical, editorLayouts: [.horizontal(middle)])
        let replacement = Editor()

        #expect(root.replaceChild(leaf, with: .one(replacement)))
        #expect(middle.editorLayouts == [.one(replacement)])
        #expect(replacement.parent === middle)
        #expect(!root.replaceChild(SplitViewData(.vertical), with: .one(Editor())))
    }
}
