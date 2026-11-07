//
//  FileSystemOutlineView.swift
//  Dreamder
//
//  Created by TAY KAI QUAN on 14/8/22.
//

import SwiftUI

class FileSystemTableViewCell: StandardTableViewCell {

    weak var fileItem: CEWorkspaceFile?

    private var navigatorFilter: String?

    /// Initializes the `OutlineTableViewCell` with an `icon` and `label`
    /// Both the icon and label will be colored, and sized based on the user's preferences.
    /// - Parameters:
    ///   - frameRect: The frame of the cell.
    ///   - item: The file item the cell represents.
    ///   - isEditable: Set to true if the user should be able to edit the file name.
    ///   - navigatorFilter: An optional string use to filter the navigator area.
    ///                      (Used for bolding and changing primary/secondary color).
    init(frame frameRect: NSRect, item: CEWorkspaceFile?, isEditable: Bool = true, navigatorFilter: String? = nil) {
        super.init(frame: frameRect, isEditable: isEditable)
        self.navigatorFilter = navigatorFilter

        if let item = item {
            addIcon(item: item)
        }
    }

    override func configLabel(label: NSTextField, isEditable: Bool) {
        super.configLabel(label: label, isEditable: isEditable)
        label.delegate = self
    }

    func addIcon(item: CEWorkspaceFile) {
        fileItem = item
        let iconName: String
        if item.isFolder {
            let isExcluded = ExcludedDirectories.rules(covering: item.url).isExclusionRoot(item.url)
            iconName = isExcluded ? "nodes/excludeRoot" : "nodes/folder"
        } else {
            iconName = IntelliJIcon.fileIcon(for: item.name)
        }
        if let image = IntelliJIcon.nsImage(iconName) {
            imageView?.image = image
        } else {
            imageView?.image = item.nsIcon
        }
        imageView?.imageScaling = .scaleProportionallyDown
        imageView?.contentTintColor = nil

        let fileName = item.labelFileName()
        let fontSize = Islands.uiFontSize
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingMiddle
        paragraphStyle.alignment = .left

        let attributedString = NSMutableAttributedString(string: fileName, attributes: [
            .paragraphStyle: paragraphStyle,
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: nameColor(for: item)
        ])

        if let filter = navigatorFilter?.trimmingCharacters(in: .whitespacesAndNewlines), !filter.isEmpty {
            let range = (fileName as NSString).range(of: filter, options: .caseInsensitive)
            if range.location != NSNotFound {
                attributedString.addAttributes([
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                    .foregroundColor: NSColor(Islands.foreground)
                ], range: range)
            } else {
                attributedString.addAttribute(
                    .foregroundColor,
                    value: NSColor(Islands.secondaryForeground),
                    range: NSRange(location: 0, length: attributedString.length)
                )
            }
        }

        textField?.attributedStringValue = attributedString
    }

    /// The color of a file's name based on its VCS status, matching IntelliJ's project view.
    func nameColor(for item: CEWorkspaceFile) -> NSColor {
        guard let gitStatus = item.gitStatus else { return NSColor(Islands.foreground) }
        switch gitStatus {
        case .modified, .renamed, .copied, .fileTypeChange:
            return NSColor(Islands.fileModified)
        case .added:
            return NSColor(Islands.fileAdded)
        case .untracked:
            return NSColor(Islands.fileUnversioned)
        case .deleted:
            return NSColor(Islands.fileDeleted)
        case .unmerged:
            return NSColor(Islands.fileConflict)
        case .none:
            return NSColor(Islands.foreground)
        }
    }

    /// *Not Implemented*
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    /// *Not Implemented*
    required init?(coder: NSCoder) {
        nil
    }

    /// Returns the font size for the current row height. Defaults to `13.0`
    private var fontSize: Double {
        switch self.frame.height {
        case 20: return 11
        case 22: return 13
        case 24: return 14
        default: return 13
        }
    }

    isolated deinit {
        toolTip = nil
    }
}

let errorRed = NSColor(red: 1, green: 0, blue: 0, alpha: 0.2)
extension FileSystemTableViewCell: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let fileItem else { return }
        textField?.backgroundColor = fileItem.validateFileName(for: textField?.stringValue ?? "") ? .none : errorRed
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let fileItem else { return }
        do {
            textField?.backgroundColor = fileItem.validateFileName(for: textField?.stringValue ?? "") ? .none : errorRed
            if fileItem.validateFileName(for: textField?.stringValue ?? "") {
                let newURL = fileItem.url
                    .deletingLastPathComponent()
                    .appending(path: textField?.stringValue ?? "")
                try workspace?.workspaceFileManager?.move(file: fileItem, to: newURL)
            } else {
                textField?.stringValue = fileItem.labelFileName()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.addButton(withTitle: "Dismiss")
            alert.runModal()
        }
    }
}
