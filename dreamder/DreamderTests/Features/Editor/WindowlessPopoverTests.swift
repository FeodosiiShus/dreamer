import AppKit
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct WindowlessPopoverTests {
    @Test
    func goToLinePopupIsNotPresentedForAViewWithoutAWindow() {
        let presenter = GoToLinePopupPresenter()
        let model = GoToLinePopupModel(lineCount: 30, currentLine: 4, currentColumn: 2, onSubmit: { _ in })

        presenter.present(model: model, relativeTo: NSRect(x: 0, y: 0, width: 10, height: 10), of: NSView())

        #expect(!presenter.isPresented)
        #expect(presenter.popover == nil)
    }

    @Test
    func gitGutterClickWithoutAWindowPresentsNoPopover() throws {
        let marker = GitGutterMarkerView(frame: NSRect(x: 0, y: 0, width: 12, height: 40))
        let textView = TextView(string: "alpha\nbeta\n")
        marker.textView = textView
        marker.changes = [GitLineChange(kind: .deleted, oldLines: 1...2, newLines: nil, anchorLine: 0)]
        let event = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: 6, y: 1),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )

        withExtendedLifetime(textView) { marker.mouseDown(with: event) }

        #expect(marker.popover == nil)
    }
}
