import SwiftUI

enum Islands {
    enum BackgroundImageKey {
        static let path = "dreamder.backgroundImage.path"
        static let opacity = "dreamder.backgroundImage.opacity"
        static let fill = "dreamder.backgroundImage.fill"
        static let defaultOpacity = 0.3
    }

    enum Density: String, CaseIterable, Identifiable {
        case compact
        case `default`

        var id: String { rawValue }

        var title: String {
            switch self {
            case .compact: "Compact"
            case .default: "Default"
            }
        }
    }

    static let densityKey = "dreamder.uiDensity"

    static var density: Density {
        guard let raw = UserDefaults.standard.string(forKey: densityKey),
              let density = Density(rawValue: raw) else {
            return .compact
        }
        return density
    }

    static var isCompact: Bool {
        density == .compact
    }

    static let frame = Color(hex: 0x26282C)
    static let island = Color(hex: 0x191A1C)
    static let islandRaised = Color(hex: 0x1F2024)
    static let popup = Color(hex: 0x26282C)
    static let popupBorder = Color(hex: 0x33353B)
    static let separator = Color(hex: 0x33353B)
    static let componentBorder = Color(hex: 0x40434A)
    static let foreground = Color(hex: 0xD1D3D9)
    static let secondaryForeground = Color(hex: 0x8C8F96)
    static let disabledForeground = Color(hex: 0x6F737A)
    static let editorForeground = Color(hex: 0xBCBEC4)
    static let hover = Color.white.opacity(0x10 / 255)
    static let actionHover = Color.white.opacity(0x17 / 255)
    static let selection = Color(hex: 0x2E436E)
    static let selectionInactive = Color(hex: 0x2B2D30)
    static let accent = Color(hex: 0x3871E1)
    static let link = Color(hex: 0x71A1FE)
    static let searchMatch = Color(hex: 0x71A1FE)
    static let tabSelectedBackground = Color(hex: 0x233558)
    static let tabSelectedBorder = Color(hex: 0x2E4D89)
    static let tabInactiveSelectedBackground = Color(hex: 0x26282C)
    static let tabInactiveSelectedBorder = Color(hex: 0x40434A)
    static let testFileBackground = Color(hex: 0x1C261C)
    static let stripeSelected = Color(hex: 0x3871E1)
    static let lineNumber = Color(hex: 0x4B5059)
    static let lineNumberCaretRow = Color(hex: 0xA1A3AB)
    static let caretRow = Color(hex: 0x1F2024)
    static let indentGuide = Color(hex: 0x323438)
    static let rightMargin = Color(hex: 0x323438)
    static let fileAdded = Color(hex: 0x73BD79)
    static let fileModified = Color(hex: 0x70AEFF)
    static let fileDeleted = Color(hex: 0x6F737A)
    static let fileUnversioned = Color(hex: 0xE88F89)
    static let fileIgnored = Color(hex: 0xD69A6B)
    static let fileConflict = Color(hex: 0xDE6A66)
    static let errorForeground = Color(hex: 0xDB5C5C)
    static let warningForeground = Color(hex: 0xF2C55C)
    static let successForeground = Color(hex: 0x5FB865)

    static var islandRadius: CGFloat { isCompact ? 8 : 10 }
    static var islandGap: CGFloat { isCompact ? 4 : 6 }
    static let popupRadius: CGFloat = 12
    static let controlRadius: CGFloat = 6
    static let rowRadius: CGFloat = 4
    static var mainToolbarHeight: CGFloat { isCompact ? 34 : 40 }
    static var toolbarControlHeight: CGFloat { isCompact ? 24 : 28 }
    static var toolWindowHeaderHeight: CGFloat { isCompact ? 32 : 41 }
    static var tabStripHeight: CGFloat { isCompact ? 31 : 40 }
    static var tabBarHeight: CGFloat { tabStripHeight + 1 }
    static var tabPillHeight: CGFloat { isCompact ? 24 : 30 }
    static var tabPillRadius: CGFloat { isCompact ? 4 : 6 }
    static var tabColorInset: CGFloat { isCompact ? 2 : 3 }
    static var tabLabelFontSize: CGFloat { isCompact ? 12 : 13 }
    static var statusBarHeight: CGFloat { isCompact ? 22 : 26 }
    static var stripeWidth: CGFloat { isCompact ? 33 : 40 }
    static var stripeButtonSize: CGFloat { isCompact ? 32 : 30 }
    static var stripeIconSize: CGFloat { isCompact ? 16 : 20 }
    static var treeRowHeight: CGFloat { isCompact ? 20 : 24 }
    static var listRowHeight: CGFloat { isCompact ? 20 : 24 }
    static var popupRowHeight: CGFloat { isCompact ? 22 : 26 }
    static var popupHeaderHeight: CGFloat { isCompact ? 32 : 40 }
    static var popupFooterHeight: CGFloat { isCompact ? 26 : 30 }
    static let uiFontSize: CGFloat = 13
    static let smallFontSize: CGFloat = 12
    static let codeFontName = "JetBrains Mono"
    static let codeFontSize: CGFloat = 13
    static let codeLineHeightMultiple: CGFloat = 1.7

    static let glassTintOpacity = 0.64

    static var glassIslandTint: Color { island.opacity(glassTintOpacity) }
    static var glassPopupTint: Color { popup.opacity(glassTintOpacity) }
    static var glassBorder: Color { popupBorder.opacity(0.6) }

    static var uiFont: Font { .system(size: uiFontSize) }
    static var smallFont: Font { .system(size: smallFontSize) }
    static var headerTitleFont: Font { .system(size: uiFontSize, weight: .semibold) }
    static var tabLabelFont: Font { .system(size: tabLabelFontSize) }

    static var codeFont: Font {
        .custom(codeFontName, size: codeFontSize)
    }

    static var codeNSFont: NSFont {
        NSFont(name: codeFontName, size: codeFontSize) ?? .monospacedSystemFont(ofSize: codeFontSize, weight: .regular)
    }
}

enum IntelliJIcon {
    static func image(_ name: String) -> Image {
        Image(name)
    }

    static func nsImage(_ name: String) -> NSImage? {
        NSImage(named: name)
    }

    static func fileIcon(for fileName: String) -> String {
        let lower = fileName.lowercased()
        switch (lower as NSString).pathExtension {
        case "swift": return "fileTypes/swiftLang"
        case "java": return "fileTypes/java"
        case "class": return "fileTypes/javaClass"
        case "js", "mjs", "cjs", "jsx": return "fileTypes/javaScript"
        case "ts", "tsx", "mts", "cts": return "fileTypes/typeScript"
        case "json", "jsonc": return "fileTypes/json"
        case "md", "markdown": return "fileTypes/markdown"
        case "html", "htm": return "fileTypes/html"
        case "xhtml": return "fileTypes/xhtml"
        case "css", "scss", "sass", "less": return "fileTypes/css"
        case "xml", "plist", "xib", "storyboard", "iml": return "fileTypes/xml"
        case "yml", "yaml": return "fileTypes/yaml"
        case "sh", "bash", "zsh", "fish": return "fileTypes/shell"
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "ico", "icns", "tiff", "bmp": return "fileTypes/image"
        case "zip", "jar", "tar", "gz", "tgz", "xz", "7z", "rar": return "fileTypes/archive"
        case "txt", "log", "text": return "fileTypes/text"
        default:
            if lower == ".gitignore" { return "fileTypes/gitignore" }
            return "fileTypes/anyType"
        }
    }
}
