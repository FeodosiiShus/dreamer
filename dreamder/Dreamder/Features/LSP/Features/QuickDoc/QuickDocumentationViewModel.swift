import AppKit
import Observation

@MainActor
@Observable
final class QuickDocumentationViewModel {
    let blocks: [QuickDocumentationBlock]
    let size: NSSize

    @ObservationIgnored
    var dismiss: (() -> Void)?

    init(content: QuickDocumentationContent) {
        let blocks = QuickDocumentationMarkup.blocks(from: content)
        self.blocks = blocks
        self.size = Self.preferredSize(for: blocks)
    }

    init(message: String) {
        let blocks: [QuickDocumentationBlock] = [.plain(message)]
        self.blocks = blocks
        self.size = Self.preferredSize(for: blocks)
    }

    func close() {
        dismiss?()
    }

    private static func preferredSize(for blocks: [QuickDocumentationBlock]) -> NSSize {
        let maximumWidth: CGFloat = 520
        let minimumWidth: CGFloat = 220
        var width = minimumWidth
        var height: CGFloat = 20

        for block in blocks {
            let lines = block.text.split(separator: "\n", omittingEmptySubsequences: false)
            let longest = lines.map(\.count).max() ?? 0
            if block.isCode {
                width = max(width, CGFloat(longest) * 7.4 + 40)
                height += CGFloat(max(lines.count, 1)) * 16 + 20
            } else {
                let wrapped = max(Int((Double(longest) * 6.9 / (maximumWidth - 24)).rounded(.up)), 1)
                width = max(width, min(CGFloat(longest) * 6.9 + 32, maximumWidth))
                height += CGFloat(wrapped) * 17 + 8
            }
        }

        return NSSize(
            width: min(max(width, minimumWidth), maximumWidth),
            height: min(max(height, 72), 360)
        )
    }
}
