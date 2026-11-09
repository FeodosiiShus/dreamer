//
//  ProjectNavigatorNSOutlineView.swift
//  Dreamder
//
//  Created by Khan Winter on 6/10/25.
//

import AppKit

final class ProjectNavigatorNSOutlineView: NSOutlineView, NSMenuItemValidation {
    var clickedRowOverride: Int?

    override var clickedRow: Int {
        clickedRowOverride ?? super.clickedRow
    }

    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        .zero
    }

    private var controller: ProjectNavigatorViewController? {
        delegate as? ProjectNavigatorViewController
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.window === window && window?.firstResponder === self,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              controller != nil else {
            return super.performKeyEquivalent(with: event)
        }

        switch event.charactersIgnoringModifiers {
        case "c":
            copy(self)
            return true
        case "x":
            cut(self)
            return true
        case "v":
            paste(self)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    @objc
    func copy(_ sender: Any?) {
        controller?.copyToClipboard(controller?.selectedFiles ?? [])
    }

    @objc
    func cut(_ sender: Any?) {
        controller?.cutToClipboard(controller?.selectedFiles ?? [])
    }

    @objc
    func paste(_ sender: Any?) {
        controller?.pasteFromClipboard(into: controller?.selectedFiles.first)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copy(_:)), #selector(cut(_:)):
            return !selectedRowIndexes.isEmpty
        case #selector(paste(_:)):
            return controller?.canPaste == true
        case #selector(ProjectNavigatorMenu.newFileFromClipboard):
            return !selectedRowIndexes.isEmpty
        default:
            return false
        }
    }
}
