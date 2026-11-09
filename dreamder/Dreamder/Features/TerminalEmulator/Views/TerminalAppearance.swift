import AppKit
import SwiftTerm
import SwiftUI

struct TerminalAppearance: Equatable {
    static let caretAlpha: CGFloat = 0.5

    var colors: Theme.TerminalColors?
    var cursorStyle: CursorStyle
    var optionAsMeta: Bool
    var darkAppearance: Bool

    var ansiColors: [SwiftTerm.Color] {
        colors?.ansiColors.map { SwiftTerm.Color(hex: $0) } ?? []
    }

    var cursorColor: NSColor {
        colors.map { NSColor($0.cursor.swiftColor) } ?? NSColor(.accentColor)
    }

    var selectionColor: NSColor {
        colors.map { NSColor($0.selection.swiftColor) } ?? NSColor(.accentColor)
    }

    var textColor: NSColor {
        colors.map { NSColor($0.text.swiftColor) } ?? NSColor(.primary)
    }

    var nsAppearance: NSAppearance? {
        darkAppearance ? NSAppearance(named: .darkAqua) : nil
    }

    func apply(to terminal: CELocalShellTerminalView) {
        let caret = cursorColor.withAlphaComponent(Self.caretAlpha)
        terminal.appearance = nsAppearance
        terminal.installColors(ansiColors)
        terminal.caretColor = caret
        terminal.caretTextColor = caret
        terminal.selectedTextBackgroundColor = selectionColor
        terminal.nativeForegroundColor = textColor
        terminal.nativeBackgroundColor = .clear
        terminal.cursorStyleChanged(source: terminal.getTerminal(), newStyle: cursorStyle)
        terminal.layer?.backgroundColor = CGColor.clear
        terminal.optionAsMetaKey = optionAsMeta
        terminal.needsDisplay = true
    }
}
