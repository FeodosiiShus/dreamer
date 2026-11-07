import Foundation
import JavaScriptCore
import Testing
@testable import Dreamder

@Suite
struct MarkdownPreviewScrollScriptTests {
    private static let environment = """
    var window = this;
    var scrollY = 0;
    var clock = 0;
    var pendingFrames = [];
    var maxScroll = 1600;
    function scrollTo(a, b) {
      var top = typeof a === "object" ? a.top : b;
      scrollY = Math.min(Math.max(top, 0), maxScroll);
    }
    var performance = { now: function () { return clock; } };
    function requestAnimationFrame(callback) { pendingFrames.push(callback); }
    function stepFrames(milliseconds) {
      clock += milliseconds;
      var frames = pendingFrames;
      pendingFrames = [];
      frames.forEach(function (callback) { callback(clock); });
    }
    function makeElement(tag, position, top, bottom, children) {
      var node = {
        tagName: tag,
        position: position,
        top: top,
        bottom: bottom,
        firstElementChild: null,
        nextElementSibling: null,
        innerHTML: "",
        getAttribute: function (name) { return name === "md-src-pos" ? this.position : null; },
        getBoundingClientRect: function () { return { top: this.top - scrollY, bottom: this.bottom - scrollY }; },
        getClientRects: function () { return [{}]; }
      };
      var previous = null;
      (children || []).forEach(function (child) {
        if (previous) { previous.nextElementSibling = child; } else { node.firstElementChild = child; }
        previous = child;
      });
      return node;
    }
    var document = {
      body: null,
      documentElement: { scrollHeight: 2000 },
      scrollingElement: { scrollHeight: 2000, clientHeight: 400 },
      getElementById: function () { return null; }
    };
    """

    private func makeContext(body: String) throws -> JSContext {
        let context = try #require(JSContext())
        context.exceptionHandler = { _, exception in
            Issue.record("JavaScript exception: \(exception?.toString() ?? "unknown")")
        }
        context.evaluateScript(Self.environment)
        context.evaluateScript("document.body = \(body);")
        context.evaluateScript(MarkdownPreviewScripts.pageScript)
        return context
    }

    private func settle(_ context: JSContext) -> Double {
        for _ in 0..<400 {
            context.evaluateScript("stepFrames(16);")
        }
        return context.evaluateScript("scrollY")?.toDouble() ?? -1
    }

    private let flatBody = """
    makeElement("BODY", null, 0, 2000, [
      makeElement("P", "10..30", 100, 200),
      makeElement("P", "50..90", 260, 400),
      makeElement("H2", "100..120", 500, 560)
    ])
    """

    @Test
    func offsetInsideBlockInterpolatesBetweenItsEdges() throws {
        let context = try makeContext(body: flatBody)
        context.evaluateScript("window.dreamderPreview.scrollToSourceOffset(20);")
        #expect(abs(settle(context) - 150) < 0.5)
    }

    @Test
    func offsetBetweenBlocksInterpolatesAcrossTheGap() throws {
        let context = try makeContext(body: flatBody)
        context.evaluateScript("window.dreamderPreview.scrollToSourceOffset(40);")
        #expect(abs(settle(context) - 230) < 0.5)
    }

    @Test
    func offsetBeforeFirstBlockStartsAtDocumentTop() throws {
        let context = try makeContext(body: flatBody)
        context.evaluateScript("window.dreamderPreview.scrollToSourceOffset(0);")
        #expect(settle(context) == 0)
    }

    @Test
    func offsetPastTheLastBlockEndsAtItsBottomAndClampsToMaximumScroll() throws {
        let context = try makeContext(body: flatBody)
        context.evaluateScript("window.dreamderPreview.scrollToSourceOffset(100000);")
        #expect(abs(settle(context) - 560) < 0.5)

        let tall = """
        makeElement("BODY", null, 0, 2000, [
          makeElement("P", "0..10", 0, 100),
          makeElement("P", "20..30", 1900, 1990)
        ])
        """
        let clamped = try makeContext(body: tall)
        clamped.evaluateScript("window.dreamderPreview.scrollToSourceOffset(100000);")
        #expect(abs(settle(clamped) - 1600) < 0.5)
    }

    @Test
    func listItemsRefineTheRangeInsideTheirList() throws {
        let body = """
        makeElement("BODY", null, 0, 2000, [
          makeElement("UL", "0..100", 0, 400, [
            makeElement("LI", "0..50", 0, 200),
            makeElement("LI", "51..100", 200, 400)
          ])
        ])
        """
        let context = try makeContext(body: body)
        context.evaluateScript("window.dreamderPreview.scrollToSourceOffset(75);")
        let expected = 200 + (75.0 - 51.0) / (100.0 - 51.0) * 200
        #expect(abs(settle(context) - expected) < 0.5)
    }

    @Test
    func tableRowsAreReachedThroughSectionWrappers() throws {
        let body = """
        makeElement("BODY", null, 0, 2000, [
          makeElement("TABLE", "0..60", 0, 300, [
            makeElement("THEAD", null, 0, 100, [makeElement("TR", "0..20", 0, 100)]),
            makeElement("TBODY", null, 100, 300, [
              makeElement("TR", "30..40", 100, 200),
              makeElement("TR", "50..60", 200, 300)
            ])
          ])
        ])
        """
        let context = try makeContext(body: body)
        context.evaluateScript("window.dreamderPreview.scrollToSourceOffset(35);")
        #expect(abs(settle(context) - 150) < 0.5)
    }

    @Test
    func followingMovesExponentiallyWithFortyMillisecondTimeConstant() throws {
        let context = try makeContext(body: flatBody)
        context.evaluateScript("window.dreamderPreview.scrollToSourceOffset(20);")
        context.evaluateScript("stepFrames(16);")
        let afterFirstFrame = context.evaluateScript("scrollY")?.toDouble() ?? -1
        let expected = 150 * (1 - exp(-16.0 / 40.0))
        #expect(abs(afterFirstFrame - expected) < 0.01)
        context.evaluateScript("stepFrames(16);")
        let afterSecondFrame = context.evaluateScript("scrollY")?.toDouble() ?? -1
        let secondExpected = afterFirstFrame + (150 - afterFirstFrame) * (1 - exp(-16.0 / 40.0))
        #expect(abs(afterSecondFrame - secondExpected) < 0.01)
        #expect(MarkdownPreviewScripts.followTimeMilliseconds == 40)
    }

    @Test
    func manualScrollingCancelsTheFollowAnimation() throws {
        let context = try makeContext(body: flatBody)
        context.evaluateScript("window.dreamderPreview.scrollToSourceOffset(100);")
        context.evaluateScript("stepFrames(16);")
        context.evaluateScript("scrollY = 900;")
        let settled = settle(context)
        #expect(settled == 900)
    }

    @Test
    func newTargetsRetargetTheRunningAnimation() throws {
        let context = try makeContext(body: flatBody)
        context.evaluateScript("window.dreamderPreview.scrollToSourceOffset(100);")
        context.evaluateScript("stepFrames(16);")
        context.evaluateScript("window.dreamderPreview.scrollToSourceOffset(20);")
        #expect(abs(settle(context) - 150) < 0.5)
    }

    @Test
    func replacingTheBodyKeepsTheScrollPosition() throws {
        let context = try makeContext(body: flatBody)
        context.evaluateScript("scrollY = 321;")
        context.evaluateScript("window.dreamderPreview.replaceBody('<p>x</p>', false);")
        #expect(context.evaluateScript("scrollY")?.toDouble() == 321)
        #expect(context.evaluateScript("document.body.innerHTML")?.toString() == "<p>x</p>")
    }

    @Test
    func replacingTheBodyReappliesTheFollowTargetWhenSyncing() throws {
        let context = try makeContext(body: flatBody)
        context.evaluateScript("window.dreamderPreview.scrollToSourceOffset(20);")
        _ = settle(context)
        context.evaluateScript("scrollY = 0;")
        context.evaluateScript("window.dreamderPreview.replaceBody('<p>x</p>', true);")
        context.evaluateScript("document.body = \(flatBody);")
        #expect(abs(settle(context) - 150) < 0.5)
    }

    @Test
    func scrollScriptCallsTheFollowEntryPoint() {
        #expect(
            MarkdownPreviewScripts.scrollScript(offset: 42)
                == "window.dreamderPreview && window.dreamderPreview.scrollToSourceOffset(42);"
        )
        #expect(MarkdownPreviewScripts.positionAttribute == "md-src-pos")
    }
}
