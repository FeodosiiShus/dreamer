import AppKit

enum BranchesPopupPrompt {
    static func name(title: String, message: String, placeholder: String, initialValue: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: initialValue)
        field.placeholderString = placeholder
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func confirm(title: String, message: String, confirmTitle: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func error(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    static func branchDialog(_ request: BranchesPopupBranchDialogRequest) -> BranchesPopupBranchDialogResult? {
        BranchesPopupBranchDialogController(request: request).run()
    }

    static func unmergedDelete(name: String, commits: [String]) -> BranchesPopupDeleteBranchDecision {
        let alert = NSAlert()
        alert.messageText = "Branch '\(name)' is not fully merged"
        var message = "The branch contains commits that are not merged anywhere:\n\n"
        message += commits.prefix(15).joined(separator: "\n")
        if commits.count > 15 {
            message += "\n…"
        }
        message += "\n\nDelete the branch anyway?"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Force Delete")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .force : .cancel
    }

    static func localCommitsDecision(
        local: String,
        remote: String,
        count: Int
    ) -> BranchesPopupLocalCommitsDecision {
        let alert = NSAlert()
        alert.messageText = "Local branch '\(local)' has commits that do not exist in '\(remote)'"
        alert.informativeText = """
        \(local) has \(count) commit(s) not present in \(remote). Rebase \(local) onto \(remote), or drop local commits?
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Rebase")
        alert.addButton(withTitle: "Drop Local Commits")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .rebase
        case .alertSecondButtonReturn: return .drop
        default: return .cancel
        }
    }
}

private final class BranchesPopupBranchDialogController: NSObject, NSTextFieldDelegate {
    private let request: BranchesPopupBranchDialogRequest
    private let alert = NSAlert()
    private let field: NSTextField
    private let overwriteBox = NSButton(checkboxWithTitle: "Overwrite existing branch", target: nil, action: nil)
    private let checkoutBox = NSButton(checkboxWithTitle: "Checkout branch", target: nil, action: nil)
    private let unsetBox = NSButton(checkboxWithTitle: "Unset upstream", target: nil, action: nil)
    private let errorLabel = NSTextField(labelWithString: "")

    init(request: BranchesPopupBranchDialogRequest) {
        self.request = request
        self.field = NSTextField(string: request.initialName)
        super.init()
    }

    func run() -> BranchesPopupBranchDialogResult? {
        field.placeholderString = "Branch name"
        field.delegate = self
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.frame = NSRect(x: 0, y: 0, width: 300, height: 16)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.frame = NSRect(x: 0, y: 0, width: 300, height: 80)
        stack.addArrangedSubview(field)
        if request.showsCheckout {
            checkoutBox.state = .on
            checkoutBox.target = self
            checkoutBox.action = #selector(updateValidation)
            stack.addArrangedSubview(checkoutBox)
        }
        overwriteBox.target = self
        overwriteBox.action = #selector(updateValidation)
        stack.addArrangedSubview(overwriteBox)
        if request.showsUnsetUpstream {
            stack.addArrangedSubview(unsetBox)
        }
        stack.addArrangedSubview(errorLabel)
        stack.setFrameSize(stack.fittingSize)

        alert.messageText = request.title
        alert.informativeText = request.message
        alert.alertStyle = .informational
        alert.addButton(withTitle: request.confirmTitle)
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = stack
        alert.window.initialFirstResponder = field
        updateValidation()

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return BranchesPopupBranchDialogResult(
            name: name,
            checkout: request.showsCheckout ? checkoutBox.state == .on : false,
            overwrite: overwriteBox.state == .on,
            unsetUpstream: request.showsUnsetUpstream ? unsetBox.state == .on : false
        )
    }

    @objc private func updateValidation() {
        let name = field.stringValue
        let validation = BranchesPopupBranchName.validate(name, existingNames: request.existingNames)
        let exists = validation == .exists
        overwriteBox.isEnabled = exists
        if !exists {
            overwriteBox.state = .off
        }
        let overwrite = overwriteBox.state == .on
        let accepted: Bool
        switch validation {
        case .valid:
            accepted = true
        case .exists:
            accepted = overwrite
        case .empty, .invalid:
            accepted = false
        }
        errorLabel.stringValue = BranchesPopupBranchName.errorMessage(
            for: validation == .exists && overwrite ? .valid : validation,
            name: name
        ) ?? ""
        alert.buttons.first?.isEnabled = accepted
    }

    func controlTextDidChange(_ notification: Notification) {
        updateValidation()
    }
}
