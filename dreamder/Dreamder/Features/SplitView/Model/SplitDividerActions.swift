import SwiftUI

struct SplitDividerActions {
    let pair: Int
    let paneCount: Int
    let coordinator: Binding<SplitPaneCoordinator>
    let commit: ([CGFloat]) -> Void

    func drag(_ translation: CGFloat) {
        commit(coordinator.wrappedValue.dragged(pair: pair, translation: translation))
    }

    func endDrag() {
        coordinator.wrappedValue.endDrag()
    }

    func nudge(_ delta: CGFloat) {
        commit(coordinator.wrappedValue.nudged(pair: pair, delta: delta))
    }

    func equalize() {
        commit(SplitLayoutMath.equalWeights(count: paneCount))
    }
}
