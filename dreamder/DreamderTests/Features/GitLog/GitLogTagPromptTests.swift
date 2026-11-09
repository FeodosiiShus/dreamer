import AppKit
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct GitLogTagPromptTests {
    private struct Controls {
        let name: NSTextField
        let message: NSTextField
        let force: NSButton
    }

    private func dialogControls(of alert: NSAlert) -> Controls? {
        guard let stack = alert.accessoryView as? NSStackView else { return nil }
        let fields = stack.arrangedSubviews.compactMap { $0 as? NSTextField }
        guard let name = fields.first(where: { $0.placeholderString == "Tag name" }),
              let message = fields.first(where: { $0.placeholderString != "Tag name" }),
              let force = stack.arrangedSubviews.compactMap({ $0 as? NSButton }).first else { return nil }
        return Controls(name: name, message: message, force: force)
    }

    private func notifyChange(_ field: NSTextField) {
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
    }

    @Test
    func acceptableNamesAreNonEmptyWithoutWhitespace() {
        #expect(GitLogTagPrompt.isAcceptableName("v1.0"))
        #expect(GitLogTagPrompt.isAcceptableName("") == false)
        #expect(GitLogTagPrompt.isAcceptableName("v 1") == false)
        #expect(GitLogTagPrompt.isAcceptableName("v\t1") == false)
    }

    @Test
    func dialogDescribesTheCommitAndValidatesWhileTyping() throws {
        var captured: NSAlert?
        var buttonStates: [Bool] = []

        let result = GitLogTagPrompt.run(GitLogTagRequest(commit: "abcd1234")) { alert in
            captured = alert
            guard let controls = dialogControls(of: alert) else { return .abort }
            buttonStates.append(alert.buttons.first?.isEnabled ?? true)
            controls.name.stringValue = "has space"
            notifyChange(controls.name)
            buttonStates.append(alert.buttons.first?.isEnabled ?? true)
            controls.name.stringValue = "  v1.0  "
            notifyChange(controls.name)
            buttonStates.append(alert.buttons.first?.isEnabled ?? false)
            controls.message.stringValue = "  release  "
            controls.force.state = .on
            return .alertFirstButtonReturn
        }

        let alert = try #require(captured)
        #expect(alert.messageText == "Create New Tag On abcd1234")
        #expect(alert.informativeText == "Enter the name of new tag")
        #expect(alert.buttons.map(\.title) == ["Create Tag", "Cancel"])
        #expect(buttonStates == [false, false, true])
        #expect(result == GitLogTagResult(name: "v1.0", message: "release", force: true))
    }

    @Test
    func dialogWithoutMessageOrForceReportsDefaults() {
        let result = GitLogTagPrompt.run(GitLogTagRequest(commit: "abcd1234")) { alert in
            dialogControls(of: alert)?.name.stringValue = "v2"
            return .alertFirstButtonReturn
        }

        #expect(result == GitLogTagResult(name: "v2", message: "", force: false))
    }

    @Test
    func cancellingReturnsNil() {
        let result = GitLogTagPrompt.run(GitLogTagRequest(commit: "abcd1234")) { _ in
            .alertSecondButtonReturn
        }

        #expect(result == nil)
    }

    @Test
    func defaultRunnerIsSuppressedByTheHeadlessHost() {
        let before = DreamderHeadless.suppressedModals.count

        let result = GitLogTagPrompt.run(GitLogTagRequest(commit: "feedbeef"))

        #expect(result == nil)
        #expect(DreamderHeadless.suppressedModals.dropFirst(before).contains("Create New Tag On feedbeef"))
    }
}
