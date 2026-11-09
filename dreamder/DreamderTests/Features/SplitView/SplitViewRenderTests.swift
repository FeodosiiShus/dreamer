import AppKit
import Observation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class PaneFrameRecorder {
    var frames: [Int: CGRect] = [:]
}

@MainActor
@Observable
private final class WeightsModel {
    var weights: [CGFloat]
    var paneCount: Int

    init(_ weights: [CGFloat], paneCount: Int = 0) {
        self.weights = weights
        self.paneCount = paneCount
    }
}

private struct RecordedPane: View {
    let index: Int
    let recorder: PaneFrameRecorder

    var body: some View {
        Color.clear
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named("split"))
            } action: { frame in
                recorder.frames[index] = frame
            }
    }
}

private struct CountedSplit: View {
    @Bindable var model: WeightsModel
    let recorder: PaneFrameRecorder

    var body: some View {
        SplitView(axis: .horizontal, weights: $model.weights) {
            ForEach(0..<model.paneCount, id: \.self) { index in
                RecordedPane(index: index, recorder: recorder)
            }
        }
    }
}

private struct ModelBackedSplit<Content: View>: View {
    @Bindable var model: WeightsModel
    let axis: Axis
    let dividerStyle: DreamderDividerStyle
    @ViewBuilder var content: Content

    var body: some View {
        SplitView(axis: axis, dividerStyle: dividerStyle, weights: $model.weights) {
            content
        }
    }
}

private final class ShiftingView: NSView {
    private var measurements: CGFloat = 0

    override var intrinsicContentSize: NSSize {
        measurements += 7
        return NSSize(width: 10 + measurements, height: 20)
    }
}

private struct ShiftingRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> ShiftingView {
        ShiftingView()
    }

    func updateNSView(_ nsView: ShiftingView, context: Context) {
        nsView.invalidateIntrinsicContentSize()
    }
}

private struct RecordedShiftingPane: View {
    let index: Int
    let recorder: PaneFrameRecorder

    var body: some View {
        ShiftingRepresentable()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named("split"))
            } action: { frame in
                recorder.frames[index] = frame
            }
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct SplitViewRenderTests {
    private struct Harness {
        let window: NSWindow
        let host: NSHostingView<AnyView>
    }

    private func makeHarness<Content: View>(size: CGSize, @ViewBuilder content: () -> Content) -> Harness {
        let root = AnyView(
            content()
                .frame(width: size.width, height: size.height)
                .coordinateSpace(.named("split"))
        )
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        return Harness(window: window, host: host)
    }

    private func settle(_ harness: Harness) async throws {
        for _ in 0..<6 {
            harness.host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
    }

    private func expectFrame(
        _ frame: CGRect?,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let frame else {
            Issue.record("missing pane frame", sourceLocation: sourceLocation)
            return
        }
        #expect(abs(frame.minX - x) < 0.5, "minX \(frame.minX) != \(x)", sourceLocation: sourceLocation)
        #expect(abs(frame.minY - y) < 0.5, "minY \(frame.minY) != \(y)", sourceLocation: sourceLocation)
        #expect(abs(frame.width - width) < 0.5, "width \(frame.width) != \(width)", sourceLocation: sourceLocation)
        #expect(abs(frame.height - height) < 0.5, "height \(frame.height) != \(height)", sourceLocation: sourceLocation)
    }

    @Test
    func twoPanesHorizontalSplitEvenly() async throws {
        let recorder = PaneFrameRecorder()
        let harness = makeHarness(size: CGSize(width: 407, height: 300)) {
            SplitView(axis: .horizontal, dividerStyle: .system(.thin)) {
                RecordedPane(index: 0, recorder: recorder)
                RecordedPane(index: 1, recorder: recorder)
            }
        }
        try await settle(harness)

        expectFrame(recorder.frames[0], x: 0, y: 0, width: 203, height: 300)
        expectFrame(recorder.frames[1], x: 204, y: 0, width: 203, height: 300)
    }

    @Test
    func twoPanesVerticalSplitEvenly() async throws {
        let recorder = PaneFrameRecorder()
        let harness = makeHarness(size: CGSize(width: 300, height: 407)) {
            SplitView(axis: .vertical, dividerStyle: .system(.thin)) {
                RecordedPane(index: 0, recorder: recorder)
                RecordedPane(index: 1, recorder: recorder)
            }
        }
        try await settle(harness)

        expectFrame(recorder.frames[0], x: 0, y: 0, width: 300, height: 203)
        expectFrame(recorder.frames[1], x: 0, y: 204, width: 300, height: 203)
    }

    @Test
    func threePanesHorizontalUseEditorDividerThickness() async throws {
        let recorder = PaneFrameRecorder()
        let harness = makeHarness(size: CGSize(width: 306, height: 200)) {
            SplitView(axis: .horizontal, dividerStyle: .editorDivider) {
                RecordedPane(index: 0, recorder: recorder)
                RecordedPane(index: 1, recorder: recorder)
                RecordedPane(index: 2, recorder: recorder)
            }
        }
        try await settle(harness)

        expectFrame(recorder.frames[0], x: 0, y: 0, width: 100, height: 200)
        expectFrame(recorder.frames[1], x: 103, y: 0, width: 100, height: 200)
        expectFrame(recorder.frames[2], x: 206, y: 0, width: 100, height: 200)
    }

    @Test
    func threePanesVerticalFollowWeights() async throws {
        let recorder = PaneFrameRecorder()
        let model = WeightsModel([0.5, 0.25, 0.25])
        let harness = makeHarness(size: CGSize(width: 200, height: 402)) {
            ModelBackedSplit(model: model, axis: .vertical, dividerStyle: .system(.thin)) {
                RecordedPane(index: 0, recorder: recorder)
                RecordedPane(index: 1, recorder: recorder)
                RecordedPane(index: 2, recorder: recorder)
            }
        }
        try await settle(harness)

        expectFrame(recorder.frames[0], x: 0, y: 0, width: 200, height: 200)
        expectFrame(recorder.frames[1], x: 0, y: 201, width: 200, height: 100)
        expectFrame(recorder.frames[2], x: 0, y: 302, width: 200, height: 100)
        #expect(model.weights == [0.5, 0.25, 0.25])
    }

    @Test
    func collapsedPaneTakesNoSpaceAndLosesItsDivider() async throws {
        let recorder = PaneFrameRecorder()
        let harness = makeHarness(size: CGSize(width: 201, height: 100)) {
            SplitView(axis: .horizontal, dividerStyle: .system(.thin)) {
                RecordedPane(index: 0, recorder: recorder)
                RecordedPane(index: 1, recorder: recorder)
                    .collapsable()
                    .collapsed(.constant(true))
                RecordedPane(index: 2, recorder: recorder)
            }
        }
        try await settle(harness)

        expectFrame(recorder.frames[0], x: 0, y: 0, width: 100, height: 100)
        expectFrame(recorder.frames[1], x: 101, y: 0, width: 0, height: 100)
        expectFrame(recorder.frames[2], x: 101, y: 0, width: 100, height: 100)
    }

    @Test
    func collapsedFlagIsIgnoredWithoutCollapsable() async throws {
        let recorder = PaneFrameRecorder()
        let harness = makeHarness(size: CGSize(width: 201, height: 100)) {
            SplitView(axis: .horizontal, dividerStyle: .system(.thin)) {
                RecordedPane(index: 0, recorder: recorder)
                RecordedPane(index: 1, recorder: recorder)
                    .collapsed(.constant(true))
            }
        }
        try await settle(harness)

        expectFrame(recorder.frames[0], x: 0, y: 0, width: 100, height: 100)
        expectFrame(recorder.frames[1], x: 101, y: 0, width: 100, height: 100)
    }

    @Test
    func explicitMinimumAndMaximumAreHonoured() async throws {
        let recorder = PaneFrameRecorder()
        let model = WeightsModel([0.1, 0.9])
        let harness = makeHarness(size: CGSize(width: 401, height: 100)) {
            ModelBackedSplit(model: model, axis: .horizontal, dividerStyle: .system(.thin)) {
                RecordedPane(index: 0, recorder: recorder)
                    .splitPaneMinLength(150)
                RecordedPane(index: 1, recorder: recorder)
            }
        }
        try await settle(harness)

        expectFrame(recorder.frames[0], x: 0, y: 0, width: 150, height: 100)
        expectFrame(recorder.frames[1], x: 151, y: 0, width: 250, height: 100)

        let capped = PaneFrameRecorder()
        let cappedHarness = makeHarness(size: CGSize(width: 401, height: 100)) {
            SplitView(axis: .horizontal, dividerStyle: .system(.thin)) {
                RecordedPane(index: 0, recorder: capped)
                    .splitPaneMaxLength(100)
                RecordedPane(index: 1, recorder: capped)
            }
        }
        try await settle(cappedHarness)

        expectFrame(capped.frames[0], x: 0, y: 0, width: 100, height: 100)
        expectFrame(capped.frames[1], x: 101, y: 0, width: 300, height: 100)
    }

    @Test
    func weightsBindingDrivesLayoutAndRoundTrips() async throws {
        let recorder = PaneFrameRecorder()
        let model = WeightsModel([0.75, 0.25])
        let harness = makeHarness(size: CGSize(width: 401, height: 100)) {
            ModelBackedSplit(model: model, axis: .horizontal, dividerStyle: .system(.thin)) {
                RecordedPane(index: 0, recorder: recorder)
                RecordedPane(index: 1, recorder: recorder)
            }
        }
        try await settle(harness)

        expectFrame(recorder.frames[0], x: 0, y: 0, width: 300, height: 100)
        expectFrame(recorder.frames[1], x: 301, y: 0, width: 100, height: 100)
        #expect(model.weights == [0.75, 0.25])

        model.weights = [0.25, 0.75]
        try await settle(harness)

        expectFrame(recorder.frames[0], x: 0, y: 0, width: 100, height: 100)
        expectFrame(recorder.frames[1], x: 101, y: 0, width: 300, height: 100)
        #expect(model.weights == [0.25, 0.75])
    }

    @Test
    func mismatchedWeightsAreReplacedByNormalizedEqualWeights() async throws {
        let recorder = PaneFrameRecorder()
        let model = WeightsModel([1])
        let harness = makeHarness(size: CGSize(width: 301, height: 100)) {
            ModelBackedSplit(model: model, axis: .horizontal, dividerStyle: .system(.thin)) {
                RecordedPane(index: 0, recorder: recorder)
                RecordedPane(index: 1, recorder: recorder)
                RecordedPane(index: 2, recorder: recorder)
            }
        }
        try await settle(harness)

        #expect(model.weights.count == 3)
        #expect(model.weights.allSatisfy { abs($0 - 1.0 / 3) < 1e-9 })
        expectFrame(recorder.frames[0], x: 0, y: 0, width: 100, height: 100)
        expectFrame(recorder.frames[1], x: 101, y: 0, width: 100, height: 100)
        expectFrame(recorder.frames[2], x: 202, y: 0, width: 99, height: 100)
    }

    @Test
    func structureChangeRewritesWeightsAndLayout() async throws {
        let recorder = PaneFrameRecorder()
        let model = WeightsModel([0.5, 0.5], paneCount: 2)
        let harness = makeHarness(size: CGSize(width: 301, height: 100)) {
            CountedSplit(model: model, recorder: recorder)
        }
        try await settle(harness)

        #expect(model.weights == [0.5, 0.5])
        expectFrame(recorder.frames[0], x: 0, y: 0, width: 150, height: 100)
        expectFrame(recorder.frames[1], x: 151, y: 0, width: 150, height: 100)

        model.paneCount = 3
        try await settle(harness)

        #expect(model.weights.count == 3)
        #expect(model.weights.allSatisfy { abs($0 - 1.0 / 3) < 1e-9 })
        expectFrame(recorder.frames[0], x: 0, y: 0, width: 100, height: 100)
        expectFrame(recorder.frames[1], x: 101, y: 0, width: 100, height: 100)
        expectFrame(recorder.frames[2], x: 202, y: 0, width: 99, height: 100)
    }

    @Test
    func layoutIsStableAcrossRepeatedPasses() async throws {
        let recorder = PaneFrameRecorder()
        let model = WeightsModel([0.3, 0.3, 0.4])
        let harness = makeHarness(size: CGSize(width: 613, height: 377)) {
            ModelBackedSplit(model: model, axis: .horizontal, dividerStyle: .editorDivider) {
                RecordedPane(index: 0, recorder: recorder)
                RecordedPane(index: 1, recorder: recorder)
                    .splitPaneMinLength(90)
                RecordedPane(index: 2, recorder: recorder)
            }
        }
        try await settle(harness)
        let before = recorder.frames

        harness.host.layoutSubtreeIfNeeded()
        harness.host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        harness.host.layoutSubtreeIfNeeded()

        #expect(before.count == 3)
        #expect(recorder.frames == before)
        #expect(!harness.host.needsLayout)
        #expect(!harness.host.needsUpdateConstraints)
    }

    @Test
    func paneWithChangingFittingSizeDoesNotDisturbFrames() async throws {
        let recorder = PaneFrameRecorder()
        let model = WeightsModel([0.5, 0.5])
        let harness = makeHarness(size: CGSize(width: 401, height: 100)) {
            ModelBackedSplit(model: model, axis: .horizontal, dividerStyle: .system(.thin)) {
                RecordedShiftingPane(index: 0, recorder: recorder)
                RecordedPane(index: 1, recorder: recorder)
            }
        }
        try await settle(harness)

        expectFrame(recorder.frames[0], x: 0, y: 0, width: 200, height: 100)
        expectFrame(recorder.frames[1], x: 201, y: 0, width: 200, height: 100)
        let before = recorder.frames

        for _ in 0..<5 {
            harness.host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
            #expect(recorder.frames == before)
        }
        #expect(model.weights == [0.5, 0.5])
        #expect(!harness.host.needsLayout)
        #expect(!harness.host.needsUpdateConstraints)
    }

    @Test
    func unspecifiedProposalMeasuresTheMinimumPaneLengthsWithoutCrossExtent() async throws {
        let row = PaneFrameRecorder()
        let rowHarness = makeHarness(size: CGSize(width: 301, height: 100)) {
            SplitView(axis: .horizontal, dividerStyle: .system(.thin)) {
                Color.clear.splitPaneMinLength(40)
                Color.clear.splitPaneMinLength(40)
            }
            .fixedSize()
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named("split"))
            } action: { frame in
                row.frames[0] = frame
            }
        }
        let column = PaneFrameRecorder()
        let columnHarness = makeHarness(size: CGSize(width: 100, height: 301)) {
            SplitView(axis: .vertical, dividerStyle: .system(.thin)) {
                Color.clear.splitPaneMinLength(40)
                Color.clear.splitPaneMinLength(40)
            }
            .fixedSize()
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named("split"))
            } action: { frame in
                column.frames[0] = frame
            }
        }
        try await settle(rowHarness)
        try await settle(columnHarness)

        #expect(row.frames[0]?.size == CGSize(width: 81, height: 0))
        #expect(column.frames[0]?.size == CGSize(width: 0, height: 81))
    }
}
