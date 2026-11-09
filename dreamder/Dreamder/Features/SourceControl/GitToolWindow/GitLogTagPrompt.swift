import AppKit

struct GitLogTagRequest: Equatable {
    let commit: String
}

struct GitLogTagResult: Equatable {
    let name: String
    let message: String
    let force: Bool
}

enum GitLogTagPrompt {
    static func run(
        _ request: GitLogTagRequest,
        runModal: BranchesPopupPrompt.ModalRunner = BranchesPopupPrompt.systemRunner
    ) -> GitLogTagResult? {
        let controller = GitLogTagPromptController()
        return withExtendedLifetime(controller) { controller.run(request, runModal) }
    }

    static func isAcceptableName(_ name: String) -> Bool {
        !name.isEmpty && name.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    }
}

private final class GitLogTagPromptController: NSObject, NSTextFieldDelegate {
    private let alert = NSAlert()
    private let nameField = NSTextField(string: "")
    private let messageField = NSTextField(string: "")
    private let forceBox = NSButton(checkboxWithTitle: "Force", target: nil, action: nil)

    func run(_ request: GitLogTagRequest, _ runModal: BranchesPopupPrompt.ModalRunner) -> GitLogTagResult? {
        nameField.placeholderString = "Tag name"
        nameField.delegate = self
        nameField.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        messageField.placeholderString = "Message (creates an annotated tag)"
        messageField.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        forceBox.toolTip = "Force creation of the tag even if another tag with such name already exists."

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.frame = NSRect(x: 0, y: 0, width: 300, height: 80)
        stack.addArrangedSubview(nameField)
        stack.addArrangedSubview(messageField)
        stack.addArrangedSubview(forceBox)
        stack.setFrameSize(stack.fittingSize)

        alert.messageText = "Create New Tag On \(request.commit)"
        alert.informativeText = "Enter the name of new tag"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Create Tag")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = stack
        alert.window.initialFirstResponder = nameField
        updateValidation()

        guard runModal(alert) == .alertFirstButtonReturn else { return nil }
        return GitLogTagResult(
            name: nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            message: messageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            force: forceBox.state == .on
        )
    }

    private func updateValidation() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        alert.buttons.first?.isEnabled = GitLogTagPrompt.isAcceptableName(name)
    }

    func controlTextDidChange(_ notification: Notification) {
        updateValidation()
    }
}
