import AppKit
import Testing
@testable import Dreamder

@MainActor
private func makeScrollView(documentHeight: CGFloat?) -> NSScrollView {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
    if let documentHeight {
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: documentHeight))
    }
    return scrollView
}

@MainActor
private func registerTransientScrollView(in coordinator: MergeScrollCoordinator) {
    coordinator.register(makeScrollView(documentHeight: 1000), id: "transient")
}

@MainActor
private func originY(_ scrollView: NSScrollView) -> CGFloat {
    scrollView.contentView.bounds.origin.y
}

@MainActor
@Suite(.uiGate)
struct MergeScrollCoordinatorCoverageTests {
    @Test
    func scrollingOnePaneMovesTheOthersByTheSameFraction() async throws {
        let coordinator = MergeScrollCoordinator()
        let left = makeScrollView(documentHeight: 1000)
        let result = makeScrollView(documentHeight: 2100)
        let right = makeScrollView(documentHeight: 600)
        coordinator.register(left, id: "left")
        coordinator.register(result, id: "result")
        coordinator.register(right, id: "right")

        left.contentView.scroll(to: NSPoint(x: 0, y: 450))
        left.reflectScrolledClipView(left.contentView)

        try await eventually { originY(result) == 1000 && originY(right) == 250 }
        #expect(originY(left) == 450)
    }

    @Test
    func scrollingPastTheEndClampsTheFractionToOne() async throws {
        let coordinator = MergeScrollCoordinator()
        let source = makeScrollView(documentHeight: 1000)
        let follower = makeScrollView(documentHeight: 500)
        coordinator.register(source, id: "source")
        coordinator.register(follower, id: "follower")

        source.contentView.scroll(to: NSPoint(x: 0, y: 900))
        source.reflectScrolledClipView(source.contentView)

        try await eventually { originY(follower) == 400 }
    }

    @Test
    func sourceWithoutDocumentViewSyncsOthersToTheTop() async throws {
        let coordinator = MergeScrollCoordinator()
        let source = makeScrollView(documentHeight: nil)
        let follower = makeScrollView(documentHeight: 500)
        coordinator.register(source, id: "source")
        coordinator.register(follower, id: "follower")
        follower.contentView.scroll(to: NSPoint(x: 0, y: 200))
        follower.reflectScrolledClipView(follower.contentView)
        try await eventually { originY(follower) == 200 }

        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: source.contentView)

        try await eventually { originY(follower) == 0 }
    }

    @Test
    func panesWithoutDocumentViewAreSkippedWhileSyncing() async throws {
        let coordinator = MergeScrollCoordinator()
        let source = makeScrollView(documentHeight: 1000)
        let empty = makeScrollView(documentHeight: nil)
        let follower = makeScrollView(documentHeight: 1000)
        coordinator.register(source, id: "source")
        coordinator.register(empty, id: "empty")
        coordinator.register(follower, id: "follower")

        source.contentView.scroll(to: NSPoint(x: 0, y: 300))
        source.reflectScrolledClipView(source.contentView)

        try await eventually { originY(follower) == 300 }
        #expect(originY(empty) == 0)
    }

    @Test
    func releasedScrollViewsAreSkippedWhileSyncing() async throws {
        let coordinator = MergeScrollCoordinator()
        let source = makeScrollView(documentHeight: 1000)
        let follower = makeScrollView(documentHeight: 1000)
        coordinator.register(source, id: "source")
        coordinator.register(follower, id: "follower")
        registerTransientScrollView(in: coordinator)

        source.contentView.scroll(to: NSPoint(x: 0, y: 300))
        source.reflectScrolledClipView(source.contentView)

        try await eventually { originY(follower) == 300 }
    }

    @Test
    func registeringTheSameScrollViewAgainKeepsOneObserver() async throws {
        let coordinator = MergeScrollCoordinator()
        let source = makeScrollView(documentHeight: 1000)
        let follower = makeScrollView(documentHeight: 1000)
        coordinator.register(source, id: "source")
        coordinator.register(source, id: "source")
        coordinator.register(follower, id: "follower")

        source.contentView.scroll(to: NSPoint(x: 0, y: 100))
        source.reflectScrolledClipView(source.contentView)

        try await eventually { originY(follower) == 100 }
    }

    @Test
    func registeringAnotherScrollViewUnderTheSameIDReplacesTheFirst() async throws {
        let coordinator = MergeScrollCoordinator()
        let first = makeScrollView(documentHeight: 1000)
        let replacement = makeScrollView(documentHeight: 1000)
        let follower = makeScrollView(documentHeight: 1000)
        coordinator.register(first, id: "pane")
        coordinator.register(follower, id: "follower")
        coordinator.register(replacement, id: "pane")

        first.contentView.scroll(to: NSPoint(x: 0, y: 500))
        first.reflectScrolledClipView(first.contentView)
        try await Task.sleep(for: .milliseconds(100))
        #expect(originY(follower) == 0)

        replacement.contentView.scroll(to: NSPoint(x: 0, y: 200))
        replacement.reflectScrolledClipView(replacement.contentView)
        try await eventually { originY(follower) == 200 }
        #expect(originY(first) == 500)
    }

    @Test
    func unregisteredPanesNeitherDriveNorFollow() async throws {
        let coordinator = MergeScrollCoordinator()
        let source = makeScrollView(documentHeight: 1000)
        let follower = makeScrollView(documentHeight: 1000)
        let bystander = makeScrollView(documentHeight: 1000)
        coordinator.register(source, id: "source")
        coordinator.register(follower, id: "follower")
        coordinator.register(bystander, id: "bystander")
        coordinator.unregister(id: "bystander")
        coordinator.unregister(id: "never-registered")

        source.contentView.scroll(to: NSPoint(x: 0, y: 250))
        source.reflectScrolledClipView(source.contentView)
        try await eventually { originY(follower) == 250 }
        #expect(originY(bystander) == 0)

        bystander.contentView.scroll(to: NSPoint(x: 0, y: 700))
        bystander.reflectScrolledClipView(bystander.contentView)
        try await Task.sleep(for: .milliseconds(100))
        #expect(originY(source) == 250)
        #expect(originY(follower) == 250)
    }

    @Test
    func deinitRemovesTheObservers() async throws {
        var coordinator: MergeScrollCoordinator? = MergeScrollCoordinator()
        let source = makeScrollView(documentHeight: 1000)
        let follower = makeScrollView(documentHeight: 1000)
        coordinator?.register(source, id: "source")
        coordinator?.register(follower, id: "follower")
        coordinator = nil

        source.contentView.scroll(to: NSPoint(x: 0, y: 300))
        source.reflectScrolledClipView(source.contentView)
        try await Task.sleep(for: .milliseconds(100))

        #expect(originY(follower) == 0)
    }
}
