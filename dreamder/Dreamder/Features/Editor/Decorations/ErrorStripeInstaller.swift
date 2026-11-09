import AppKit
import CodeEditSourceEditor
import CodeEditTextView

@MainActor
final class ErrorStripeInstaller {
    var onSelect: ((Int) -> Void)?

    private weak var stripeView: ErrorStripeView?
    private weak var scrollView: NSScrollView?
    private var frameObserver: NSObjectProtocol?

    func install(in controller: TextViewController) {
        guard stripeView == nil, let scrollView = controller.scrollView else { return }
        let view = ErrorStripeView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.frame = Self.stripeFrame(in: scrollView)
        view.onSelect = { [weak self] line in self?.onSelect?(line) }
        scrollView.addSubview(view)
        stripeView = view
        self.scrollView = scrollView
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncFrame()
            }
        }
    }

    func update(marks: [ErrorStripeMark], lineCount: Int) {
        guard let stripeView else { return }
        if stripeView.marks != marks {
            stripeView.marks = marks
        }
        if stripeView.lineCount != lineCount {
            stripeView.lineCount = lineCount
        }
    }

    func syncFrame() {
        guard let stripeView, let scrollView else { return }
        let frame = Self.stripeFrame(in: scrollView)
        if stripeView.frame != frame {
            stripeView.frame = frame
        }
    }

    func remove() {
        if let frameObserver {
            NotificationCenter.default.removeObserver(frameObserver)
        }
        frameObserver = nil
        stripeView?.removeFromSuperview()
        stripeView = nil
        scrollView = nil
    }

    private static func stripeFrame(in scrollView: NSScrollView) -> NSRect {
        NSRect(
            x: max(0, scrollView.bounds.width - ErrorStripeView.stripWidth),
            y: 0,
            width: ErrorStripeView.stripWidth,
            height: scrollView.bounds.height
        )
    }
}
