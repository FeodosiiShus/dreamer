import SwiftUI

enum MainToolbarMetrics {
    static let buttonSize: CGFloat = 30
    static let iconSize: CGFloat = 20
    static let runIconSize: CGFloat = 16
    static let chevronSize: CGFloat = 16
    static let chevronGap: CGFloat = 2
    static let dropdownIconTextGap: CGFloat = 6
    static let dropdownMargin = EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 6)
    static let dropdownMaxWidth: CGFloat = 350
    static let runWidgetSpacing: CGFloat = 4
    static let projectAvatarSize: CGFloat = 20
    static let searchFieldWidth: CGFloat = 260
    static let searchFieldIconSize: CGFloat = 16
    static let searchFieldIconTextGap: CGFloat = 6
    static let searchFieldPadding: CGFloat = 8
    static let searchFieldBorderWidth: CGFloat = 1

    static var searchFieldHeight: CGFloat {
        Islands.toolbarControlHeight
    }

    static var searchFieldRadius: CGFloat {
        Islands.isCompact ? 3 : 4
    }

    static let runIconColor = Color(hex: 0x4E9D6C)
    static let defaultIconColor = Color(hex: 0xC3C5CB)
}
