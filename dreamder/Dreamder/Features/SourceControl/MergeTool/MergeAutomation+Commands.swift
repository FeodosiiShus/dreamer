import AppKit
import Foundation

extension MergeAutomation {
    static func resolveBlock(blockID: String, side: String) async {
        guard let model = targetRevisionsModel, let id = Int(blockID) else { return }
        let resolution: ThreeWayMerge.Resolution
        switch side {
        case "left": resolution = .left
        case "right": resolution = .right
        case "ignored": resolution = .ignored
        default: return
        }
        await model.requestResolve(id, with: resolution, window: nil)
    }

    static func applyNonConflicting(mode: String) async {
        guard let model = targetRevisionsModel else { return }
        switch mode {
        case "left": await model.requestApplyNonConflicting(.left, window: nil)
        case "all": await model.requestApplyNonConflicting(.all, window: nil)
        case "right": await model.requestApplyNonConflicting(.right, window: nil)
        default: return
        }
    }

    static func clickChip(pane: String, blockID: Int, action: String) {
        guard let window = targetRevisionsWindow,
              let contentView = window.contentView,
              let textView = findTextView(in: contentView, identifier: "merge-pane-\(pane)"),
              let storage = textView.textStorage,
              let target = NSURL(string: "merge-block://\(action)/\(blockID)") else { return }
        var location: Int?
        storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            if let url = value as? NSURL, url == target {
                location = range.location
                stop.pointee = true
            }
        }
        guard let location else { return }
        textView.clicked(onLink: target, at: location)
    }

    private static func findTextView(in view: NSView, identifier: String) -> NSTextView? {
        if let textView = view as? NSTextView, textView.identifier?.rawValue == identifier {
            return textView
        }
        for subview in view.subviews {
            if let found = findTextView(in: subview, identifier: identifier) {
                return found
            }
        }
        return nil
    }
}
