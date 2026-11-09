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

    private(set) var exclusion: ProjectNavigatorExclusion = .included

    static let excludedIconAlpha: CGFloat = 0.55

    /// Initializes the `OutlineTableViewCell` with an `icon` and `label`
    /// Both the icon and label will be colored, and sized based on the user's preferences.
    /// - Parameters:
    ///   - frameRect: The frame of the cell.
    ///   - item: The file item the cell represents.
    ///   - isEditable: Set to true if the user should be able to edit the file name.
    ///   - navigatorFilter: An optional string use to filter the navigator area.
    ///                      (Used for bolding and changing primary/secondary color).
    init(
        frame frameRect: NSRect,
        item: CEWorkspaceFile?,
        isEditable: Bool = true,
        navigatorFilter: String? = nil,
        exclusion: ProjectNavigatorExclusion = .included
    ) {
        super.init(frame: frameRect, isEditable: isEditable)
        self.navigatorFilter = navigatorFilter
        self.exclusion = exclusion

        if let item = item {
            addIcon(item: item)
        }
    }

    override func configLabel(label: NSTextField, isEditable: Bool) {
        super.configLabel(label: label, isEditable: isEditable)
        label.delegate = self
    }

    func addIcon(item: CEWorkspaceFile, imageNamed: (String) -> NSImage? = { IntelliJIcon.nsImage($0) }) {
        fileItem = item
        let iconName: String
        if item.isFolder {
            iconName = exclusion == .excludedRoot ? "nodes/excludeRoot" : "nodes/folder"
        } else {
            iconName = IntelliJIcon.fileIcon(for: item.name)
        }
        if let image = imageNamed(iconName) {
            imageView?.image = image
        } else {
            imageView?.image = item.nsIcon
        }
        imageView?.imageScaling = .scaleProportionallyDown
        imageView?.contentTintColor = nil
        imageView?.alphaValue = exclusion.isExcluded && item.isFolder ? Self.excludedIconAlpha : 1

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
        switch item.gitStatus {
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
        case nil, .some(.none):
            return exclusionNameColor(for: item)
        }
    }

    private func exclusionNameColor(for item: CEWorkspaceFile) -> NSColor {
        guard exclusion.isExcluded else { return NSColor(Islands.foreground) }
        return NSColor(item.isFolder ? Islands.secondaryForeground : Islands.fileIgnored)
    }

    /// *Not Implemented*
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    /// *Not Implemented*
    required init?(coder: NSCoder) {
        nil
    }

    isolated deinit {
        toolTip = nil
    }
}

let errorRed = NSColor(red: 1, green: 0, blue: 0, alpha: 0.2)
extension FileSystemTableViewCell: NSTextFieldDelegate {
    var enteredName: String {
        textField?.stringValue ?? ""
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let fileItem else { return }
        textField?.backgroundColor = fileItem.validateFileName(for: enteredName) ? .none : errorRed
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let fileItem else { return }
        let isValid = fileItem.validateFileName(for: enteredName)
        textField?.backgroundColor = isValid ? .none : errorRed
        guard isValid else {
            textField?.stringValue = fileItem.labelFileName()
            return
        }
        let newURL = fileItem.url
            .deletingLastPathComponent()
            .appending(path: enteredName)
        guard let manager = workspace?.workspaceFileManager else { return }
        Task.immediate {
            do {
                try await manager.move(file: fileItem, to: newURL)
            } catch {
                let alert = NSAlert(error: error)
                alert.addButton(withTitle: "Dismiss")
                alert.runModal()
            }
        }
    }
}
