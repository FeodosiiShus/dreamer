import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct UsagesAndQuickDocViewModelTests {
    private func row(_ line: Int) -> LSPUsageRow {
        LSPUsageRow(
            uri: "file:///tmp/project/main.swift",
            fileURL: URL(fileURLWithPath: "/tmp/project/main.swift"),
            fileName: "main.swift",
            fileIconName: "fileTypes/swiftLang",
            relativeDirectory: "",
            line: line,
            column: 1,
            lineText: "let value = \(line)",
            matchRange: nil
        )
    }

    private func keyEvent(_ keyCode: UInt16, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    @Test
    func usagesHeaderCountAndHeightFollowRows() {
        let one = ShowUsagesViewModel(rows: [row(1)], symbol: "value")
        #expect(one.headerTitle == "Usages of value")
        #expect(one.countText == "1 usage")
        #expect(one.panelWidth == 620)
        #expect(one.preferredHeight == 64)

        let many = ShowUsagesViewModel(rows: (1...40).map(row), symbol: "")
        #expect(many.headerTitle == "Usages")
        #expect(many.countText == "40 usages")
        #expect(many.preferredHeight == 420)

        let message = ShowUsagesViewModel(message: "No usages found")
        #expect(message.isMessage)
        #expect(message.panelWidth == 380)
        #expect(message.preferredHeight == 80)
        #expect(message.selectedRow == nil)
    }

    @Test
    func arrowKeysWrapAndEnterOpensTheSelectedUsage() throws {
        let model = ShowUsagesViewModel(rows: [row(1), row(2), row(3)], symbol: "value")
        var opened: [Int] = []
        var closed = 0
        model.openRow = { opened.append($0.line) }
        model.dismiss = { closed += 1 }

        #expect(model.handle(event: try keyEvent(126)))
        #expect(model.selectedIndex == 2)
        #expect(model.handle(event: try keyEvent(125)))
        #expect(model.selectedIndex == 0)
        #expect(model.handle(event: try keyEvent(125)))
        #expect(model.handle(event: try keyEvent(36)))
        #expect(opened == [2])
        #expect(model.handle(event: try keyEvent(76)))
        #expect(opened == [2, 2])

        model.select(7)
        #expect(model.selectedIndex == 1)
        model.select(2)
        #expect(model.selectedRow?.line == 3)

        #expect(model.handle(event: try keyEvent(125, flags: .command)) == false)
        #expect(model.handle(event: try keyEvent(0)) == false)
        #expect(model.handle(event: try keyEvent(53)))
        #expect(closed == 1)
    }

    @Test
    func emptyUsagesIgnoreNavigation() {
        let model = ShowUsagesViewModel(message: "Nothing")
        var opened = 0
        model.openRow = { _ in opened += 1 }
        model.moveSelection(1)
        model.activate()
        #expect(model.selectedIndex == 0)
        #expect(opened == 0)
    }

    @Test
    func quickDocSizeStaysWithinPopupBounds() {
        let short = QuickDocumentationViewModel(message: "Hi")
        #expect(short.blocks == [.plain("Hi")])
        #expect(short.size.width == 220)
        #expect(short.size.height == 72)

        let longProse = String(repeating: "word ", count: 400)
        let long = QuickDocumentationViewModel(content: QuickDocumentationContent(text: longProse, isMarkdown: false))
        #expect(long.size.width == 520)
        #expect(long.size.height == 360)

        let code = QuickDocumentationViewModel(
            content: QuickDocumentationContent(text: "```swift\nfunc run(argument: Int) -> String\n```", isMarkdown: true)
        )
        #expect(code.blocks.contains { $0.isCode })
        #expect(code.size.width > 220)
        #expect(code.size.width <= 520)

        var closed = false
        code.dismiss = { closed = true }
        code.close()
        #expect(closed)
    }
}
