//
//  OutlineTableViewCell.swift
//  Dreamder
//
//  Created by Lukas Pistrol on 07.04.22.
//

import SwiftUI

protocol OutlineTableViewCellDelegate: AnyObject {
    func moveFile(file: CEWorkspaceFile, to destination: URL)
    func copyFile(file: CEWorkspaceFile, to destination: URL)
    func cellDidFinishEditing()
}

/// A `NSTableCellView` showing an ``icon`` and a ``label``
final class ProjectNavigatorTableViewCell: FileSystemTableViewCell {
    private weak var delegate: OutlineTableViewCellDelegate?

    private let disclosureButton = NSButton()
    private let disclosureWidth: CGFloat = 14

    var showsDisclosureGutter = true {
        didSet { resizeSubviews(withOldSize: .zero) }
    }

    var isExpandable = false {
        didSet {
            disclosureButton.isHidden = !isExpandable
            resizeSubviews(withOldSize: .zero)
        }
    }

    var isExpanded = false {
        didSet { updateDisclosureImage() }
    }

    var onToggleDisclosure: (() -> Void)?

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
        delegate: OutlineTableViewCellDelegate? = nil,
        navigatorFilter: String? = nil
    ) {
        super.init(frame: frameRect, item: item, isEditable: isEditable, navigatorFilter: navigatorFilter)
        self.textField?.setAccessibilityIdentifier("ProjectNavigatorTableViewCell-\(item?.name ?? "")")
        self.delegate = delegate

        disclosureButton.isBordered = false
        disclosureButton.imagePosition = .imageOnly
        disclosureButton.setButtonType(.momentaryChange)
        disclosureButton.contentTintColor = NSColor(Islands.secondaryForeground)
        disclosureButton.target = self
        disclosureButton.action = #selector(toggleDisclosure)
        disclosureButton.isHidden = true
        addSubview(disclosureButton)

        updateDisclosureImage()
        resizeSubviews(withOldSize: .zero)
    }

    /// *Not Implemented*
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        fatalError("""
        init(frame: ) isn't implemented on `OutlineTableViewCell`.
        Please use `.init(frame: NSRect, item: WorkspaceClient.FileItem?)
        """)
    }

    /// *Not Implemented*
    required init?(coder: NSCoder) {
        fatalError("""
        init?(coder: NSCoder) isn't implemented on `OutlineTableViewCell`.
        Please use `.init(frame: NSRect, item: WorkspaceClient.FileItem?)
        """)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        guard let imageView, let textField else { return }

        let leadingInset: CGFloat = 6
        let gutter = showsDisclosureGutter ? disclosureWidth : 0
        let shift = leadingInset + gutter
        imageView.frame.origin.x += shift
        textField.frame.origin.x += shift
        textField.frame.size.width = max(0, textField.frame.width - shift)

        let size = disclosureWidth
        disclosureButton.frame = NSRect(
            x: leadingInset,
            y: (bounds.height - size) / 2,
            width: size,
            height: size
        )
    }

    private func updateDisclosureImage() {
        let symbolName = isExpanded ? "chevron.down" : "chevron.right"
        let configuration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        disclosureButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        disclosureButton.contentTintColor = NSColor(Islands.secondaryForeground)
    }

    @objc private func toggleDisclosure() {
        onToggleDisclosure?()
    }

    override func controlTextDidEndEditing(_ obj: Notification) {
        guard let fileItem else { return }
        textField?.backgroundColor = fileItem.validateFileName(for: textField?.stringValue ?? "") ? .none : errorRed
        if fileItem.validateFileName(for: textField?.stringValue ?? "") {
            let destinationURL = fileItem.url
                .deletingLastPathComponent()
                .appending(path: textField?.stringValue ?? "")
            delegate?.moveFile(file: fileItem, to: destinationURL)
        } else {
            textField?.stringValue = fileItem.labelFileName()
        }
        delegate?.cellDidFinishEditing()
    }
}
