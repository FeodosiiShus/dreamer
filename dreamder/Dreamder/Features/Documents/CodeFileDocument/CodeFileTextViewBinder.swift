import CodeEditSourceEditor
import CodeEditTextView
import Foundation

final class CodeFileTextViewBinder: TextViewCoordinator, TextViewDelegate {
    private weak var document: CodeFileDocument?
    private weak var boundController: TextViewController?

    init(document: CodeFileDocument) {
        self.document = document
    }

    func prepareCoordinator(controller: TextViewController) {
        boundController = controller
        document?.attachedController = controller
    }

    func textView(_ textView: TextView, willReplaceContentsIn range: NSRange, with string: String) {
        document?.trackWillReplace(range: range, in: textView)
    }

    func textView(_ textView: TextView, didReplaceContentsIn range: NSRange, with string: String) {
        document?.trackDidReplace(range: range, with: string, in: textView)
    }

    func destroy() {
        if let document, document.attachedController === boundController {
            document.attachedController = nil
        }
        boundController = nil
    }
}
