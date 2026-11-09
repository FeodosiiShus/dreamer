import AppKit
import Foundation
import LanguageServerProtocol

nonisolated struct SignatureHelpCapability: Equatable, Sendable {
    static let fallbackTriggerCharacters = ["(", ","]

    let triggerCharacters: Set<String>
    let retriggerCharacters: Set<String>

    init?(staticOptions: SignatureHelpOptions?, isDynamicallyRegistered: Bool, dynamicOptions: [SignatureHelpOptions]) {
        guard staticOptions != nil || isDynamicallyRegistered else { return nil }
        let declaredTriggers = dynamicOptions.compactMap(\.triggerCharacters).first
            ?? staticOptions?.triggerCharacters
            ?? []
        let declaredRetriggers = dynamicOptions.compactMap(\.retriggerCharacters).first
            ?? staticOptions?.retriggerCharacters
            ?? []
        triggerCharacters = Set(declaredTriggers.isEmpty ? Self.fallbackTriggerCharacters : declaredTriggers)
        retriggerCharacters = Set(declaredRetriggers)
    }
}

nonisolated enum SignatureHelpTriggerPolicy {
    static func context(
        typed string: String,
        capability: SignatureHelpCapability,
        activeSignatureHelp: SignatureHelp?
    ) -> SignatureHelpContext? {
        guard string.count == 1 else { return nil }
        let isOpen = activeSignatureHelp != nil
        let triggers = capability.triggerCharacters.contains(string)
        let retriggers = isOpen && capability.retriggerCharacters.contains(string)
        guard triggers || retriggers else { return nil }
        return .typed(string, activeSignatureHelp: activeSignatureHelp)
    }
}

nonisolated enum SignatureHelpCallRegion {
    private static let openParen: UInt16 = 0x28
    private static let closeParen: UInt16 = 0x29
    private static let lineFeed: UInt16 = 0x0A

    static func enclosingOpenParen(before caret: Int, in units: [UInt16]) -> Int? {
        var depth = 0
        var index = min(caret, units.count) - 1
        while index >= 0 {
            switch units[index] {
            case closeParen:
                depth += 1
            case openParen:
                if depth == 0 {
                    return index
                }
                depth -= 1
            default:
                break
            }
            index -= 1
        }
        return nil
    }

    static func matchingCloseParen(of openIndex: Int, in units: [UInt16]) -> Int? {
        guard units.indices.contains(openIndex), units[openIndex] == openParen else { return nil }
        var depth = 0
        for index in (openIndex + 1)..<units.count {
            switch units[index] {
            case openParen:
                depth += 1
            case closeParen:
                if depth == 0 {
                    return index
                }
                depth -= 1
            default:
                break
            }
        }
        return nil
    }

    static func contains(caret: Int, openParen openIndex: Int, in units: [UInt16]) -> Bool {
        guard units.indices.contains(openIndex), units[openIndex] == openParen, caret > openIndex else { return false }
        guard let close = matchingCloseParen(of: openIndex, in: units) else { return true }
        return caret <= close
    }

    static func shifted(openParen openIndex: Int, forEditIn range: NSRange, replacementLength: Int) -> Int? {
        if range.location > openIndex {
            return openIndex
        }
        if range.upperBound <= openIndex {
            return openIndex + replacementLength - range.length
        }
        return nil
    }

    static func position(ofOffset offset: Int, in units: [UInt16]) -> Position {
        let end = min(max(offset, 0), units.count)
        var line = 0
        var lineStart = 0
        for index in 0..<end where units[index] == lineFeed {
            line += 1
            lineStart = index + 1
        }
        return Position(line: line, character: end - lineStart)
    }
}

nonisolated enum SignatureHelpKeyAction: Equatable, Sendable {
    case dismiss
    case previousSignature
    case nextSignature

    static let escapeKeyCode: UInt16 = 53
    static let upArrowKeyCode: UInt16 = 126
    static let downArrowKeyCode: UInt16 = 125

    static func resolve(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        signatureCount: Int
    ) -> SignatureHelpKeyAction? {
        let relevant = modifiers.intersection([.shift, .control, .option, .command])
        let cycles = signatureCount > 1 && (relevant.isEmpty || relevant == .option)
        switch keyCode {
        case escapeKeyCode:
            return relevant.isEmpty ? .dismiss : nil
        case upArrowKeyCode:
            return cycles ? .previousSignature : nil
        case downArrowKeyCode:
            return cycles ? .nextSignature : nil
        default:
            return nil
        }
    }
}

nonisolated enum SignatureHelpPlacement {
    static let gap: CGFloat = 4
    static let screenMargin: CGFloat = 8

    static func frame(size: NSSize, anchor: NSRect, visibleFrame: NSRect?) -> NSRect {
        let aboveY = anchor.maxY + gap
        let belowY = anchor.minY - size.height - gap
        var origin = NSPoint(x: anchor.minX, y: aboveY)
        if let visibleFrame {
            let fitsAbove = aboveY + size.height <= visibleFrame.maxY - screenMargin
            let fitsBelow = belowY >= visibleFrame.minY + screenMargin
            let aboveSpace = visibleFrame.maxY - anchor.maxY
            let belowSpace = anchor.minY - visibleFrame.minY
            if !fitsAbove && (fitsBelow || belowSpace > aboveSpace) {
                origin.y = belowY
            }
            origin.x = min(max(origin.x, visibleFrame.minX + screenMargin), visibleFrame.maxX - size.width - screenMargin)
            origin.y = min(max(origin.y, visibleFrame.minY + screenMargin), visibleFrame.maxY - size.height - screenMargin)
        }
        return NSRect(origin: origin, size: size)
    }
}
