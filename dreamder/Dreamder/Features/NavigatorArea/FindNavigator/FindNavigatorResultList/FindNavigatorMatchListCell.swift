//
//  FindNavigatorListCell.swift
//  Dreamder
//
//  Created by Khan Winter on 7/7/22.
//

import SwiftUI

/// A `NSTableCellView` showing an icon and label
final class FindNavigatorListMatchCell: NSTableCellView {

    private var label: NSTextField!
    private var matchItem: SearchResultMatchModel

    init(frame: CGRect, matchItem: SearchResultMatchModel) {
        self.matchItem = matchItem
        super.init(frame: CGRect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.width,
            height: frame.height
        ))

        setUpLabel()
        self.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)
        ])
    }

    /// Sets up the `NSTextField` used as a label in the cell.
    private func setUpLabel() {
        self.label = NSTextField(wrappingLabelWithString: matchItem.lineContent)
        self.label.translatesAutoresizingMaskIntoConstraints = false
        self.label.drawsBackground = false
        self.label.isEditable = false
        self.label.isSelectable = false
        self.label.font = Islands.codeNSFont
        self.label.allowsDefaultTighteningForTruncation = false
        self.label.cell?.truncatesLastVisibleLine = true
        self.label.cell?.wraps = true
        self.label.maximumNumberOfLines = Settings.shared.preferences.general.findNavigatorDetail.rawValue
        self.label.attributedStringValue = Self.attributedString(for: matchItem)
    }

    static func attributedString(for matchItem: SearchResultMatchModel) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: matchItem.attributedLabel())
        let fullRange = NSRange(location: 0, length: result.length)
        result.addAttributes([
            .font: Islands.codeNSFont,
            .foregroundColor: NSColor(Islands.secondaryForeground)
        ], range: fullRange)

        let matchRange = NSRange(matchItem.keywordRange, in: matchItem.lineContent)
        if matchRange.location != NSNotFound, NSMaxRange(matchRange) <= result.length {
            result.addAttributes([
                .foregroundColor: NSColor(Islands.foreground),
                .backgroundColor: NSColor(Islands.searchMatch).withAlphaComponent(0.3)
            ], range: matchRange)
        }
        return result
    }

    required init?(coder: NSCoder) {
        fatalError()
    }
}
