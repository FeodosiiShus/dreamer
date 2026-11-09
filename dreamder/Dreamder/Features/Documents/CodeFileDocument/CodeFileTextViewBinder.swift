import CodeEditSourceEditor
import CodeEditTextView
import Foundation

final class CodeFileTextViewBinder: TextViewCoordinator, TextViewDelegate {
    private struct BoundController {
        weak var controller: TextViewController?
    }

    private weak var document: CodeFileDocument?
    private var boundControllers: [BoundController] = []

    init(document: CodeFileDocument) {
        self.document = document
    }

    func prepareCoordinator(controller: TextViewController) {
        boundControllers.append(BoundController(controller: controller))
        document?.attachedController = controller
    }

    func textView(_ textView: TextView, willReplaceContentsIn range: NSRange, with string: String) {
        document?.trackWillReplace(range: range, in: textView)
    }

    func textView(_ textView: TextView, didReplaceContentsIn range: NSRange, with string: String) {
        document?.trackDidReplace(range: range, with: string, in: textView)
    }

    func destroy() {
        boundControllers.removeAll { $0.controller == nil }
        if document?.attachedController == nil {
            document?.attachedController = boundControllers.last?.controller
        }
    }
}
