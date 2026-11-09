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

    static func maximumLines(for matchItem: SearchResultMatchModel) -> Int {
        Settings.shared.preferences.general.findNavigatorDetail.rawValue
            * (matchItem.replacementPreviewLine == nil ? 1 : 2)
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
        label.maximumNumberOfLines = maximumLines(for: matchItem)
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

        let hasPreview = matchItem.replacementPreviewLine != nil
        let matchColor = hasPreview ? Islands.errorForeground : Islands.searchMatch
        let matchRange = NSRange(matchItem.keywordRange, in: matchItem.lineContent)
        if matchRange.location != NSNotFound, NSMaxRange(matchRange) <= result.length {
            result.addAttributes([
                .foregroundColor: NSColor(Islands.foreground),
                .backgroundColor: NSColor(matchColor).withAlphaComponent(0.3)
            ], range: matchRange)
        }

        if let preview = matchItem.replacementPreviewLine, let replacement = matchItem.replacementDisplay {
            let prefixLength = (String(matchItem.lineContent[..<matchItem.keywordRange.lowerBound]) as NSString).length
            let start = result.length + 1
            result.append(NSAttributedString(string: "\n" + preview, attributes: [
                .font: Islands.codeNSFont,
                .foregroundColor: NSColor(Islands.secondaryForeground)
            ]))
            result.addAttributes([
                .foregroundColor: NSColor(Islands.foreground),
                .backgroundColor: NSColor(Islands.successForeground).withAlphaComponent(0.3)
            ], range: NSRange(location: start + prefixLength, length: (replacement as NSString).length))
        }

        if matchItem.isSkipped {
            result.addAttributes([
                .foregroundColor: NSColor(Islands.disabledForeground),
                .strikethroughStyle: NSUnderlineStyle.single.rawValue
            ], range: NSRange(location: 0, length: result.length))
        }
        return result
    }

    required init?(coder: NSCoder) {
        nil
    }
}

final class FindNavigatorListFileCell: NSTableCellView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let directoryLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")

    init(frame: CGRect, result: SearchResultModel, projectRoot: URL?) {
        super.init(frame: frame)
        configureLabels()

        iconView.image = IntelliJIcon.nsImage(IntelliJIcon.fileIcon(for: result.file.name))
        nameLabel.stringValue = result.file.name
        directoryLabel.stringValue = Self.relativeDirectory(of: result.file.url, in: projectRoot)
        countLabel.stringValue = "\(result.lineMatches.count)"

        [iconView, nameLabel, directoryLabel, countLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            directoryLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
            directoryLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            directoryLabel.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -8),
            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    private func configureLabels() {
        nameLabel.font = .systemFont(ofSize: Islands.uiFontSize)
        nameLabel.textColor = NSColor(Islands.foreground)
        nameLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        directoryLabel.font = .systemFont(ofSize: Islands.smallFontSize)
        directoryLabel.textColor = NSColor(Islands.secondaryForeground)
        directoryLabel.lineBreakMode = .byTruncatingHead
        directoryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        countLabel.font = .systemFont(ofSize: Islands.smallFontSize)
        countLabel.textColor = NSColor(Islands.secondaryForeground)
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
    }

    var displayedName: String { nameLabel.stringValue }
    var displayedDirectory: String { directoryLabel.stringValue }
    var displayedCount: String { countLabel.stringValue }

    static func relativeDirectory(of url: URL, in root: URL?) -> String {
        let directory = url.deletingLastPathComponent().standardizedFileURL.path(percentEncoded: false)
        guard let root else { return directory }
        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        guard directory.hasPrefix(rootPath) else { return directory }
        return String(directory.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    required init?(coder: NSCoder) {
        nil
    }
}
