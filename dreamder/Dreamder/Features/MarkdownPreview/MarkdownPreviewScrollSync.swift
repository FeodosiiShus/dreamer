import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Observation

@Observable
final class MarkdownPreviewScrollState {
    private(set) var sourceOffset: Int?

    func follow(_ offset: Int) {
        guard sourceOffset != offset else { return }
        sourceOffset = offset
    }
}

final class MarkdownScrollSyncCoordinator: TextViewCoordinator {
    let scrollState = MarkdownPreviewScrollState()

    private weak var controller: TextViewController?
    private var observer: NSObjectProtocol?

    isolated deinit {
        removeObserver()
    }

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
        removeObserver()
        observer = NotificationCenter.default.addObserver(
            forName: TextViewController.scrollPositionDidUpdateNotification,
            object: controller,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.publishFirstVisibleOffset()
            }
        }
    }

    func controllerDidAppear(controller: TextViewController) {
        publishFirstVisibleOffset()
    }

    func destroy() {
        removeObserver()
        controller = nil
    }

    func publishFirstVisibleOffset() {
        guard let location = controller?.textView?.visibleTextRange?.location else { return }
        scrollState.follow(location)
    }

    private func removeObserver() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }
}
