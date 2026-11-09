import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct QuickActionsViewTests {
    private func host(
        _ model: QuickActionsViewModel,
        log: QuickActionsRunLog
    ) -> HostedView {
        HostedViewFixture.host {
            QuickActionsView(state: model, closePalette: { log.entries.append("close") })
        }
    }

    private func fieldEditor(in hosted: HostedView) throws -> NSTextView {
        let field = try #require(hosted.views(of: NSTextField.self).first { $0.isEditable })
        hosted.window.makeFirstResponder(field)
        if field.currentEditor() == nil {
            field.selectText(nil)
        }
        return try #require(field.currentEditor() as? NSTextView)
    }

    private func type(_ text: String, in hosted: HostedView) throws -> NSTextView {
        let editor = try fieldEditor(in: hosted)
        editor.insertText(text, replacementRange: editor.selectedRange())
        return editor
    }

    private func labelTitles(in hosted: HostedView) -> [String] {
        hosted.views(of: NSTextField.self).filter { !$0.isEditable }.map(\.stringValue)
    }

    @Test
    func creatingTheViewListsEveryRegisteredCommand() {
        let registration = QuickActionsRegistration(names: ["Alpha", "Beta"])
        let model = QuickActionsViewModel()
        model.filteredCommands = []

        _ = QuickActionsView(state: model, closePalette: {})

        #expect(Set(model.filteredCommands.map(\.id)).isSuperset(of: registration.ids))
    }

    @Test
    func choosingACommandClosesThePaletteThenRunsItAndClearsTheState() throws {
        let registration = QuickActionsRegistration(names: ["Alpha"])
        let model = QuickActionsViewModel()
        let log = registration.log
        let view = QuickActionsView(state: model, closePalette: { log.entries.append("close") })
        model.commandQuery = registration.token
        model.fetchMatchingCommands(val: registration.token)
        let command = try #require(model.filteredCommands.first)

        view.callHandler(command: command)

        #expect(log.entries == ["close", registration.ids[0]])
        #expect(model.commandQuery.isEmpty)
        #expect(model.filteredCommands.isEmpty)
    }

    @Test
    func typingFiltersTheRowsAndHighlightsTheQuery() async throws {
        let registration = QuickActionsRegistration(names: ["Alpha", "Beta"])
        let model = QuickActionsViewModel()
        let hosted = host(model, log: registration.log)
        defer { hosted.close() }
        try await hosted.settle()

        _ = try type(registration.token, in: hosted)

        try await eventually(timeout: .seconds(30)) {
            Set(model.filteredCommands.map(\.id)) == Set(registration.ids)
        }
        try await eventually(timeout: .seconds(30)) {
            hosted.layout()
            let titles = labelTitles(in: hosted)
            return titles.contains(registration.title("Alpha")) && titles.contains(registration.title("Beta"))
        }
        let label = try #require(
            hosted.views(of: NSTextField.self).first { $0.stringValue == registration.title("Alpha") }
        )
        var hasBoldRun = false
        label.attributedStringValue.enumerateAttribute(
            .font,
            in: NSRange(location: 0, length: label.attributedStringValue.length)
        ) { value, _, _ in
            if let font = value as? NSFont, font.fontDescriptor.symbolicTraits.contains(.bold) {
                hasBoldRun = true
            }
        }
        #expect(hasBoldRun)
    }

    @Test
    func submittingRunsTheSelectedCommandAndClosesThePalette() async throws {
        let registration = QuickActionsRegistration(names: ["Only"])
        let model = QuickActionsViewModel()
        let hosted = host(model, log: registration.log)
        defer { hosted.close() }
        try await hosted.settle()

        _ = try type(registration.title("Only"), in: hosted)
        try await eventually(timeout: .seconds(30)) {
            model.filteredCommands.map(\.id) == registration.ids
        }
        try await eventually(timeout: .seconds(30)) {
            hosted.layout()
            return hosted.views(of: NSTableView.self).first?.selectedRow == 0
        }
        try fieldEditor(in: hosted).doCommand(by: #selector(NSResponder.insertNewline(_:)))

        #expect(registration.log.entries == ["close", registration.ids[0]])
        #expect(model.commandQuery.isEmpty)
        #expect(model.filteredCommands.isEmpty)
    }
}
