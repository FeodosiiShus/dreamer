import CoreGraphics
import Testing
@testable import Dreamder

@Suite
struct EditorTabOverflowTests {
    private let viewport = CGRect(x: 100, y: 0, width: 300, height: 41)

    @Test
    func tabsInsideViewportAreNotHidden() {
        let frames: [String: CGRect] = [
            "a": CGRect(x: 104, y: 0, width: 80, height: 30),
            "b": CGRect(x: 188, y: 0, width: 80, height: 30),
            "c": CGRect(x: 272, y: 0, width: 120, height: 30)
        ]
        let hidden = EditorTabOverflow.hiddenTabs(
            openedTabs: ["a", "b", "c"],
            frames: frames,
            viewport: viewport
        )
        #expect(hidden.isEmpty)
    }

    @Test
    func tabsOutsideViewportAreHidden() {
        let frames: [String: CGRect] = [
            "a": CGRect(x: 20, y: 0, width: 60, height: 30),
            "b": CGRect(x: 104, y: 0, width: 80, height: 30),
            "c": CGRect(x: 420, y: 0, width: 80, height: 30)
        ]
        let hidden = EditorTabOverflow.hiddenTabs(
            openedTabs: ["a", "b", "c"],
            frames: frames,
            viewport: viewport
        )
        #expect(hidden == ["a", "c"])
    }

    @Test
    func partiallyVisibleTabIsHidden() {
        let frames: [String: CGRect] = [
            "a": CGRect(x: 380, y: 0, width: 80, height: 30)
        ]
        let hidden = EditorTabOverflow.hiddenTabs(
            openedTabs: ["a"],
            frames: frames,
            viewport: viewport
        )
        #expect(hidden == ["a"])
    }

    @Test
    func unmeasuredViewportHidesNothing() {
        let frames: [String: CGRect] = [
            "a": CGRect(x: 420, y: 0, width: 80, height: 30)
        ]
        let hidden = EditorTabOverflow.hiddenTabs(
            openedTabs: ["a"],
            frames: frames,
            viewport: .zero
        )
        #expect(hidden.isEmpty)
    }

    @Test
    func unmeasuredTabIsSkipped() {
        let hidden = EditorTabOverflow.hiddenTabs(
            openedTabs: ["a", "b"],
            frames: ["b": CGRect(x: 104, y: 0, width: 80, height: 30)],
            viewport: viewport
        )
        #expect(hidden.isEmpty)
    }
}
