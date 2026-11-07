//
//  FindNavigatorListCell.swift
//  Dreamder
//
//  Created by Khan Winter on 7/7/22.
//

import SwiftUI

/// A `NSTableCellView` showing an icon and label
final class FindNavigatorListMatchCell: NSTableCellView {

    private let label: NSTextField
    private var matchItem: SearchResultMatchModel

    init(frame: CGRect, matchItem: SearchResultMatchModel) {
        self.matchItem = matchItem
        self.label = Self.makeLabel(for: matchItem)
        super.init(frame: CGRect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.width,
            height: frame.height
        ))

        self.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)
        ])
    }

    private static func makeLabel(for matchItem: SearchResultMatchModel) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: matchItem.lineContent)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.font = Islands.codeNSFont
        label.allowsDefaultTighteningForTruncation = false
        label.cell?.truncatesLastVisibleLine = true
        label.cell?.wraps = true
        label.maximumNumberOfLines = Settings.shared.preferences.general.findNavigatorDetail.rawValue
        label.attributedStringValue = attributedString(for: matchItem)
        return label
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
        nil
    }
}
