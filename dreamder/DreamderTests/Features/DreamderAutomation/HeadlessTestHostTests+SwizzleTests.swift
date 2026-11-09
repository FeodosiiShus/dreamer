import AppKit
import Testing
@testable import Dreamder

@MainActor
extension HeadlessTestHostTests {
    @Test
    func aMissingSystemMethodIsRecordedAndNothingIsIntercepted() {
        var intercepted: Set<String> = ["NSAlert.runModal"]
        var missing: Set<String> = []

        DreamderHeadless.swizzle(
            nil,
            named: "NSMenu.+noSuchContextMenu:",
            with: 0,
            intercepted: &intercepted,
            missing: &missing
        )

        #expect(missing == ["NSMenu.+noSuchContextMenu:"])
        #expect(intercepted == ["NSAlert.runModal"])
    }

    @Test
    func uncaughtExceptionsWithoutAReasonAreStillReported() throws {
        let handler = try #require(NSGetUncaughtExceptionHandler())

        handler(NSException(name: .genericException, reason: nil, userInfo: nil))
    }

    @Test
    func installersWithoutAnAppKitMethodChangeNothing() {
        let intercepted = DreamderHeadless.interceptedSelectors
        let missing = DreamderHeadless.missingSelectors

        DreamderHeadless.hideBeforeOrdering(method: nil)
        DreamderHeadless.keepOffscreenFrames(method: nil)

        #expect(DreamderHeadless.interceptedSelectors == intercepted)
        #expect(DreamderHeadless.missingSelectors == missing)
    }

    @Test
    func offscreenOriginLiesBeyondEveryScreenWithAGap() {
        #expect(DreamderHeadless.origin(beyond: []) == NSPoint(x: 20_000, y: 20_000))
        let screens = [NSRect(x: 0, y: 0, width: 100, height: 50), NSRect(x: 100, y: 0, width: 200, height: 300)]
        #expect(DreamderHeadless.origin(beyond: screens) == NSPoint(x: 20_300, y: 20_300))

        let origin = DreamderHeadless.offscreenOrigin
        let probe = NSRect(origin: origin, size: NSSize(width: 10, height: 10))
        #expect(DreamderHeadless.intersectsAnyScreen(probe) == false)
    }

    @Test
    func revealingAMissingPathIsRecordedAsAnEmptyString() throws {
        let reveal = "NSWorkspace.selectFile:inFileViewerRootedAtPath:"
        try #require(DreamderHeadless.interceptedSelectors.contains(reveal))
        let before = DreamderHeadless.suppressedExternalOpens.count

        #expect(NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: "") == false)

        #expect(DreamderHeadless.suppressedExternalOpens.dropFirst(before).contains(""))
    }
}
