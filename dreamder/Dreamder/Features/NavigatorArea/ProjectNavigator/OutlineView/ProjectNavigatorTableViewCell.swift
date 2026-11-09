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
    struct CreationEditing {
        let validate: (String) -> String?
        let commit: (String) -> Void
        let cancel: () -> Void
    }

    private weak var delegate: OutlineTableViewCellDelegate?

    private let disclosureButton = NSButton()
    private let disclosureWidth: CGFloat = 14

    private var isFinishingCreation = false

    var creationEditing: CreationEditing? {
        didSet {
            guard creationEditing != nil else { return }
            textField?.stringValue = ""
            textField?.placeholderString = fileItem?.isFolder == true ? "Directory name" : "File name"
        }
    }

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
        navigatorFilter: String? = nil,
        exclusion: ProjectNavigatorExclusion = .included
    ) {
        super.init(
            frame: frameRect,
            item: item,
            isEditable: isEditable,
            navigatorFilter: navigatorFilter,
            exclusion: exclusion
        )
        self.textField?.setAccessibilityIdentifier("ProjectNavigatorTableViewCell-\(item?.name ?? "")")
        self.delegate = delegate
        configureDisclosure()
    }

    /// *Not Implemented*
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect, item: nil)
        configureDisclosure()
    }

    /// *Not Implemented*
    required init?(coder: NSCoder) {
        nil
    }

    private func configureDisclosure() {
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

    override func controlTextDidChange(_ obj: Notification) {
        guard let creationEditing else {
            super.controlTextDidChange(obj)
            return
        }
        let name = enteredName
        let isBlank = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        showCreationError(isBlank ? nil : creationEditing.validate(name))
    }

    @objc
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let creationEditing, !isFinishingCreation else { return false }
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            finishCreation(creationEditing.cancel)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            let name = enteredName
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                finishCreation(creationEditing.cancel)
            } else if let message = creationEditing.validate(name) {
                showCreationError(message)
            } else {
                finishCreation { creationEditing.commit(name) }
            }
            return true
        default:
            return false
        }
    }

    override func controlTextDidEndEditing(_ obj: Notification) {
        if let creationEditing {
            guard !isFinishingCreation else { return }
            let name = enteredName
            isFinishingCreation = true
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || creationEditing.validate(name) != nil {
                creationEditing.cancel()
            } else {
                creationEditing.commit(name)
            }
            return
        }
        guard let fileItem else { return }
        let isValid = fileItem.validateFileName(for: enteredName)
        textField?.backgroundColor = isValid ? .none : errorRed
        if isValid {
            let destinationURL = fileItem.url
                .deletingLastPathComponent()
                .appending(path: enteredName)
            delegate?.moveFile(file: fileItem, to: destinationURL)
        } else {
            textField?.stringValue = fileItem.labelFileName()
        }
        delegate?.cellDidFinishEditing()
    }

    private func finishCreation(_ action: () -> Void) {
        isFinishingCreation = true
        var ancestor = superview
        while let current = ancestor, !(current is NSOutlineView) {
            ancestor = current.superview
        }
        if let outline = ancestor {
            window?.makeFirstResponder(outline)
        }
        action()
    }

    private func showCreationError(_ message: String?) {
        textField?.toolTip = message
        textField?.textColor = NSColor(message == nil ? Islands.foreground : Islands.errorForeground)
        textField?.layer?.backgroundColor = message == nil
            ? NSColor.textBackgroundColor.cgColor
            : errorRed.cgColor
    }
}
