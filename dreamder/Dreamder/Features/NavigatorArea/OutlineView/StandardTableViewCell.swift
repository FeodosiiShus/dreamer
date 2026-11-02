//
//  StandardTableViewCell.swift
//  Dreamder
//
//  Created by TAY KAI QUAN on 17/8/22.
//

import SwiftUI

class StandardTableViewCell: NSTableCellView {

    weak var secondaryLabel: NSTextField?
    weak var workspace: WorkspaceDocument?

    var secondaryLabelRightAligned: Bool = true {
        didSet {
            resizeSubviews(withOldSize: .zero)
        }
    }

    /// Initializes the `TableViewCell` with an `icon` and `label`
    /// Both the icon and label will be colored, and sized based on the user's preferences.
    /// - Parameters:
    ///   - frameRect: The frame of the cell.
    ///   - item: The file item the cell represents.
    ///   - isEditable: Set to true if the user should be able to edit the file name.
    init(frame frameRect: NSRect, isEditable: Bool = true) {
        super.init(frame: frameRect)
        setupViews(frame: frameRect, isEditable: isEditable)

    }

    // Default init, assumes isEditable to be false
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews(frame: frameRect, isEditable: false)
    }

    private func setupViews(frame frameRect: NSRect, isEditable: Bool) {
        // Create the label
        let label = createLabel()
        configLabel(label: label, isEditable: isEditable)
        self.textField = label

        // Create the secondary label
        let secondaryLabel = createSecondaryLabel()
        configSecondaryLabel(secondaryLabel: secondaryLabel)
        self.secondaryLabel = secondaryLabel

        // Create the icon
        let icon = createIcon()
        configIcon(icon: icon)
        addSubview(icon)
        imageView = icon

        // add constraints
        createConstraints(frame: frameRect)
        addSubview(label)
        addSubview(secondaryLabel)
        addSubview(icon)
    }

    // MARK: Create and config stuff
    func createLabel() -> NSTextField {
        return SpecialSelectTextField(frame: .zero)
    }

    func configLabel(label: NSTextField, isEditable: Bool) {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.drawsBackground = false
        label.isBordered = false
        label.isEditable = isEditable
        label.isSelectable = isEditable
        label.layer?.cornerRadius = 10.0
        label.font = .labelFont(ofSize: fontSize)
        label.lineBreakMode = .byTruncatingMiddle
    }

    func createSecondaryLabel() -> NSTextField {
        return NSTextField(frame: .zero)
    }

    func configSecondaryLabel(secondaryLabel: NSTextField) {
        secondaryLabel.translatesAutoresizingMaskIntoConstraints = false
        secondaryLabel.drawsBackground = false
        secondaryLabel.isBordered = false
        secondaryLabel.isEditable = false
        secondaryLabel.isSelectable = false
        secondaryLabel.layer?.cornerRadius = 10.0
        secondaryLabel.font = .systemFont(ofSize: fontSize-2, weight: .bold)
        secondaryLabel.alignment = .center
        secondaryLabel.textColor = .secondaryLabelColor
    }

    func createIcon() -> NSImageView {
        return NSImageView(frame: .zero)
    }

    func configIcon(icon: NSImageView) {
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        icon.symbolConfiguration = .init(pointSize: fontSize, weight: .regular, scale: .medium)
    }

    func createConstraints(frame frameRect: NSRect) {
        resizeSubviews(withOldSize: .zero)
    }

    let iconWidth: CGFloat = 22
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        guard let imageView, textField != nil, secondaryLabel != nil else {
            assertionFailure(
                "Missing child view:"
                + " imageView \(imageView == nil)"
                + ", textField: \(textField == nil)"
                + ", label: \(secondaryLabel == nil)"
            )
            return
        }

        let iconSize: CGFloat = 16
        imageView.frame = NSRect(
            x: (iconWidth - iconSize) / 2,
            y: (frame.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )

        // right align the secondary label
        if secondaryLabelRightAligned {
            rightAlignSecondary()
        } else {
            // put the secondary label right after the primary label
            leftAlignSecondary()
        }
    }

    private func rightAlignSecondary() {
        guard let secondaryLabel, let textField, let imageView else { return }
        let secondLabelWidth = secondaryLabel.frame.size.width
        let newSize = secondaryLabel.sizeThatFits(
            CGSize(width: secondLabelWidth, height: CGFloat.greatestFiniteMagnitude)
        )
        let labelHeight = frame.height - 4
        // somehow, a width of 0 makes it resize properly.
        secondaryLabel.frame = NSRect(
            x: frame.width - newSize.width,
            y: 2,
            width: 0,
            height: labelHeight
        )

        textField.frame = NSRect(
            x: iconWidth + 2,
            y: 2,
            width: max(0, secondaryLabel.frame.minX - imageView.frame.maxX - 5),
            height: labelHeight
        )
    }

    private func leftAlignSecondary() {
        guard let secondaryLabel, let textField else { return }
        let labelHeight = frame.height - 4
        let mainLabelWidth = textField.frame.size.width
        let newSize = textField.sizeThatFits(CGSize(width: mainLabelWidth, height: CGFloat.greatestFiniteMagnitude))
        textField.frame = NSRect(
            x: iconWidth + 2,
            y: 2,
            width: newSize.width,
            height: labelHeight
        )
        secondaryLabel.frame = NSRect(
            x: textField.frame.maxX + 2,
            y: 2,
            width: frame.width - textField.frame.maxX - 2,
            height: labelHeight
        )
    }

    /// *Not Implemented*
    required init?(coder: NSCoder) {
        fatalError("""
            init?(coder: NSCoder) isn't implemented on `StandardTableViewCell`.
            Please use `.init(frame: NSRect, isEditable: Bool)
            """)
    }

    /// Returns the font size for the current row height. Defaults to `13.0`
    private var fontSize: Double {
        Double(Islands.uiFontSize)
    }

    class SpecialSelectTextField: NSTextField {
        override func becomeFirstResponder() -> Bool {
            let range = NSRange(
                location: 0,
                length: stringValue.distance(
                    from: stringValue.startIndex,
                    to: stringValue.lastIndex(of: ".") ?? stringValue.endIndex
                )
            )
            selectText(self)
            let editor = currentEditor()
            editor?.selectedRange = range
            return true
        }

        override func textDidBeginEditing(_ notification: Notification) {
            super.textDidBeginEditing(notification)
            wantsLayer = true
            layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        }

        override func textDidEndEditing(_ notification: Notification) {
            super.textDidEndEditing(notification)
            wantsLayer = false
            layer?.backgroundColor = nil
        }
    }
}
