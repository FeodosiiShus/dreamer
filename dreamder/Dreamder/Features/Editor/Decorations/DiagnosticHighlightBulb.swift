import AppKit
import CodeEditSourceEditor
import CodeEditTextView

@MainActor
final class IntentionBulbPresenter {
    static let leadingInset: CGFloat = 2

    var onActivate: (() -> Void)?

    private weak var bulbView: IntentionPopupBulbView?
    private weak var textView: TextView?
    private var gutterFrameObserver: NSObjectProtocol?
    private(set) var line: Int?

    func install(controller: TextViewController) {
        guard bulbView == nil,
              let gutter = Self.gutterView(in: controller.scrollView),
              let textView = controller.textView else {
            return
        }
        let view = IntentionPopupBulbView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        view.onActivate = { [weak self] in self?.onActivate?() }
        gutter.addSubview(view)
        bulbView = view
        self.textView = textView
        gutterFrameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: gutter,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reposition()
            }
        }
    }

    func show(line: Int) {
        self.line = line
        reposition()
    }

    func hide() {
        line = nil
        bulbView?.isHidden = true
    }

    func reposition() {
        guard let bulbView, let line, let position = textView?.layoutManager.textLineForIndex(line) else {
            bulbView?.isHidden = true
            return
        }
        let size = IntentionPopupBulbView.size
        let frame = NSRect(
            x: Self.leadingInset,
            y: position.yPos + max(0, (position.height - size.height) / 2),
            width: size.width,
            height: size.height
        )
        if bulbView.frame != frame {
            bulbView.frame = frame
        }
        bulbView.isHidden = false
    }

    func remove() {
        if let gutterFrameObserver {
            NotificationCenter.default.removeObserver(gutterFrameObserver)
        }
        gutterFrameObserver = nil
        bulbView?.removeFromSuperview()
        bulbView = nil
        textView = nil
        line = nil
    }

    private static func gutterView(in view: NSView?) -> GutterView? {
        guard let view else { return nil }
        if let gutter = view as? GutterView {
            return gutter
        }
        for subview in view.subviews {
            if let found = gutterView(in: subview) {
                return found
            }
        }
        return nil
    }
}
