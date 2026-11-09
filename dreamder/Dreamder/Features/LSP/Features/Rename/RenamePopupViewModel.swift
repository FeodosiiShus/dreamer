import AppKit
import Observation

@MainActor
@Observable
final class RenamePopupViewModel {
    var name: String

    let target: RenameTarget

    @ObservationIgnored
    var onConfirm: ((String) -> Void)?
    @ObservationIgnored
    var onCancel: (() -> Void)?

    init(target: RenameTarget) {
        self.target = target
        self.name = target.name
    }

    var prompt: String { RenameMessages.prompt(for: target.name) }

    var validation: RenameNameValidation {
        RenameNameValidator.validate(name, currentName: target.name)
    }

    var isConfirmEnabled: Bool { validation.isConfirmable }

    var errorMessage: String? { validation.errorMessage }

    var panelWidth: CGFloat { 380 }

    var preferredHeight: CGFloat { 104 }

    func confirm() {
        guard isConfirmEnabled else { return }
        onConfirm?(RenameNameValidator.normalized(name))
    }

    func cancel() {
        onCancel?()
    }

    func handle(event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        switch event.keyCode {
        case 53:
            cancel()
            return true
        case 36, 76:
            confirm()
            return true
        default:
            return false
        }
    }
}
