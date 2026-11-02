import AppKit
import Foundation

@MainActor
enum MergeToolConfirmation {
    @TaskLocal static var override: Bool?
    static var automationAnswer: Bool?

    static func ask(
        window: NSWindow?,
        title: String,
        message: String,
        confirmTitle: String,
        cancelTitle: String
    ) async -> Bool {
        if let override {
            return override
        }
        if let automationAnswer {
            self.automationAnswer = nil
            return automationAnswer
        }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: cancelTitle)
        alert.alertStyle = .warning

        guard let window, window.isVisible else {
            return alert.runModal() == .alertFirstButtonReturn
        }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response == .alertFirstButtonReturn)
            }
        }
    }
}
