import Foundation
import Observation

@Observable
@MainActor
final class GoToLinePopupModel {
    var input: String
    let lineCount: Int
    let currentLine: Int
    let currentColumn: Int
    @ObservationIgnored private let onSubmit: (GoToLineTarget) -> Void
    @ObservationIgnored private let onDismiss: () -> Void

    init(
        lineCount: Int,
        currentLine: Int,
        currentColumn: Int,
        onSubmit: @escaping (GoToLineTarget) -> Void,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.lineCount = lineCount
        self.currentLine = currentLine
        self.currentColumn = currentColumn
        self.onSubmit = onSubmit
        self.onDismiss = onDismiss
        input = "\(currentLine):\(currentColumn)"
    }

    var title: String {
        "Go to Line/Column"
    }

    var placeholder: String {
        "Line:column (1–\(lineCount))"
    }

    var target: GoToLineTarget? {
        GoToLineInput.parse(input, lineCount: lineCount, currentLine: currentLine)
    }

    var isValid: Bool {
        target != nil
    }

    func submit() {
        guard let target else { return }
        onSubmit(target)
        onDismiss()
    }

    func cancel() {
        onDismiss()
    }
}
