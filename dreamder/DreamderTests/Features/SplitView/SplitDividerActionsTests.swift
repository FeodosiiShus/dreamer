import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct SplitDividerActionsTests {
    @MainActor
    private final class Recorder {
        var coordinator = SplitPaneCoordinator()
        var committed: [[CGFloat]] = []
        var drags: [CGFloat] = []
        var ends = 0
        var nudges: [CGFloat] = []
        var equalizes = 0

        func makeActions(pair: Int = 0, paneCount: Int = 2) -> SplitDividerActions {
            SplitDividerActions(
                pair: pair,
                paneCount: paneCount,
                coordinator: Binding(get: { self.coordinator }, set: { self.coordinator = $0 }),
                commit: { self.committed.append($0) }
            )
        }

        func makeDivider(axis: Axis) -> SplitDivider {
            SplitDivider(
                axis: axis,
                style: .system(.thin),
                onDrag: { self.drags.append($0) },
                onDragEnd: { self.ends += 1 },
                onNudge: { self.nudges.append($0) },
                onEqualize: { self.equalizes += 1 }
            )
        }
    }

    private func record(_ recorder: Recorder) {
        recorder.coordinator.probe.record(
            panes: [SplitLayoutPane(weight: 0.5), SplitLayoutPane(weight: 0.5)],
            lengths: [100, 100]
        )
    }

    @Test
    func draggingCommitsWeightsFromTheRecordedDragOrigin() {
        let recorder = Recorder()
        record(recorder)
        let actions = recorder.makeActions()

        actions.drag(20)
        actions.drag(40)
        actions.endDrag()
        actions.drag(40)

        #expect(recorder.committed.count == 3)
        #expect(abs(recorder.committed[0][0] - 0.6) < 1e-9)
        #expect(abs(recorder.committed[1][0] - 0.7) < 1e-9)
        #expect(abs(recorder.committed[2][0] - 0.7) < 1e-9)
    }

    @Test
    func nudgingAndEqualizingCommitTheResultingWeights() {
        let recorder = Recorder()
        record(recorder)
        let actions = recorder.makeActions()

        actions.nudge(-30)
        actions.equalize()

        #expect(recorder.committed.count == 2)
        #expect(abs(recorder.committed[0][0] - 0.35) < 1e-9)
        #expect(recorder.committed[1] == [0.5, 0.5])
    }

    @Test
    func changedWeightsAreReturnedOnlyWhenTheyDifferFromTheCurrentOnes() {
        #expect(SplitPaneCoordinator.changed([0.5, 0.5], from: [0.5, 0.5]) == nil)
        #expect(SplitPaneCoordinator.changed([0.6, 0.4], from: [0.5, 0.5]) == [0.6, 0.4])
        #expect(SplitPaneCoordinator.changed([1], from: [0.5, 0.5]) == [1])
    }

    @Test
    func dividerProjectsTheDragTranslationOntoItsAxis() {
        let row = Recorder()
        let column = Recorder()

        row.makeDivider(axis: .horizontal).drag(CGSize(width: 12, height: 5))
        column.makeDivider(axis: .vertical).drag(CGSize(width: 12, height: 5))

        #expect(row.drags == [12])
        #expect(column.drags == [5])
    }
}
