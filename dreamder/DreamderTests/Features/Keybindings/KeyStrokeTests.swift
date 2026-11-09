import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@Suite
struct ShortcutModifiersTests {
    @Test
    func eventFlagsConvertAndIgnoreDeviceIndependentNoise() {
        let all: NSEvent.ModifierFlags = [.control, .option, .shift, .command, .capsLock, .function, .numericPad]
        let some: NSEvent.ModifierFlags = [.shift, .command]
        let none: NSEvent.ModifierFlags = [.capsLock]

        #expect(ShortcutModifiers(all) == [.control, .option, .shift, .command])
        #expect(ShortcutModifiers(some) == [.shift, .command])
        #expect(ShortcutModifiers(none).isEmpty)
    }

    @Test
    func swiftUIModifiersFollowTheSameSet() {
        let all: ShortcutModifiers = [.control, .option, .shift, .command]

        #expect(all.eventModifiers == [.control, .option, .shift, .command])
        #expect(ShortcutModifiers.shift.eventModifiers == .shift)
        #expect(ShortcutModifiers().eventModifiers == [])
    }

    @Test
    func glyphsAndNamesUseTheMacOrder() {
        let all: ShortcutModifiers = [.command, .shift, .option, .control]

        #expect(all.glyphs == "\u{2303}\u{2325}\u{21E7}\u{2318}")
        #expect(all.names == ["control", "option", "shift", "command"])
        #expect(ShortcutModifiers().glyphs.isEmpty)
    }

    @Test
    func onlyCommandControlAndOptionCountAsMenuModifiers() {
        #expect(ShortcutModifiers.command.hasMenuModifier)
        #expect(ShortcutModifiers.control.hasMenuModifier)
        #expect(ShortcutModifiers.option.hasMenuModifier)
        #expect(!ShortcutModifiers.shift.hasMenuModifier)
        #expect(!ShortcutModifiers().hasMenuModifier)
    }

    @Test
    func appKitFlagsRoundTripTheSet() {
        let all: ShortcutModifiers = [.control, .option, .shift, .command]

        #expect(all.eventFlags == [.control, .option, .shift, .command])
        #expect(ShortcutModifiers(all.eventFlags) == all)
        #expect(ShortcutModifiers().eventFlags.isEmpty)
    }

    @Test
    func namesParseBackToModifiers() {
        #expect(ShortcutModifiers(name: "control") == .control)
        #expect(ShortcutModifiers(name: "option") == .option)
        #expect(ShortcutModifiers(name: "shift") == .shift)
        #expect(ShortcutModifiers(name: "command") == .command)
        #expect(ShortcutModifiers(name: "meta") == nil)
    }
}

@Suite
struct KeyNamesTests {
    @Test
    func namedKeysHaveUniqueNamesKeysAndGlyphs() {
        let entries = KeyNames.entries

        #expect(Set(entries.map(\.name)).count == entries.count)
        #expect(Set(entries.map(\.key)).count == entries.count)
        #expect(Set(entries.map(\.glyph)).count == entries.count)
        #expect(entries.count == 14 + 20)
    }

    @Test
    func functionKeysCoverF1ThroughF20() {
        #expect(KeyNames.functionKeys.count == 20)
        #expect(KeyNames.f1 == "\u{F704}")
        #expect(KeyNames.f2 == "\u{F705}")
        #expect(KeyNames.f6 == "\u{F709}")
        #expect(KeyNames.f7 == "\u{F70A}")
        #expect(KeyNames.f12 == "\u{F70F}")
        #expect(KeyNames.byName["f20"]?.key == "\u{F717}")
        #expect(KeyNames.byName["f20"]?.glyph == "F20")
        #expect(KeyNames.isFunctionKey(KeyNames.f12))
        #expect(!KeyNames.isFunctionKey("a"))
    }

    @Test
    func glyphsMatchIntelliJMacKeymapUtil() {
        #expect(KeyNames.byKey[KeyNames.up]?.glyph == "\u{2191}")
        #expect(KeyNames.byKey[KeyNames.down]?.glyph == "\u{2193}")
        #expect(KeyNames.byKey[KeyNames.left]?.glyph == "\u{2190}")
        #expect(KeyNames.byKey[KeyNames.right]?.glyph == "\u{2192}")
        #expect(KeyNames.byKey[KeyNames.backspace]?.glyph == "\u{232B}")
        #expect(KeyNames.byKey[KeyNames.forwardDelete]?.glyph == "\u{2326}")
        #expect(KeyNames.byKey[KeyNames.tab]?.glyph == "\u{21E5}")
        #expect(KeyNames.byKey[KeyNames.escape]?.glyph == "\u{238B}")
        #expect(KeyNames.byKey[KeyNames.space]?.glyph == "\u{2423}")
        #expect(KeyNames.byKey[KeyNames.enter]?.glyph == "\u{23CE}")
        #expect(KeyNames.byKey[KeyNames.home]?.glyph == "\u{2196}")
        #expect(KeyNames.byKey[KeyNames.end]?.glyph == "\u{2198}")
        #expect(KeyNames.byKey[KeyNames.pageUp]?.glyph == "\u{21DE}")
        #expect(KeyNames.byKey[KeyNames.pageDown]?.glyph == "\u{21DF}")
    }

    @Test
    func keyCodesMapEveryLetterAndDigit() {
        let letters = "abcdefghijklmnopqrstuvwxyz".map { $0 }
        let digits = "0123456789".map { $0 }
        let mapped = Set(KeyNames.byKeyCode.values)

        #expect(letters.allSatisfy(mapped.contains))
        #expect(digits.allSatisfy(mapped.contains))
        #expect(KeyNames.byKeyCode.count == Set(mapped).count)
    }

    @Test
    func fallbackKeyAcceptsASingleLowercasedPrintableCharacter() {
        #expect(KeyNames.fallbackKey("\u{44F}") == "\u{44F}")
        #expect(KeyNames.fallbackKey("A") == "a")
        #expect(KeyNames.fallbackKey("7") == "7")
        #expect(KeyNames.fallbackKey("/") == "/")
        #expect(KeyNames.fallbackKey("+") == "+")
        #expect(KeyNames.fallbackKey("") == nil)
        #expect(KeyNames.fallbackKey(nil) == nil)
        #expect(KeyNames.fallbackKey("ab") == nil)
        #expect(KeyNames.fallbackKey("\u{1}") == nil)
    }
}

@Suite
struct KeyStrokeTests {
    @Test(arguments: [
        "command b",
        "command ,",
        "command [",
        "shift command ]",
        "option f7",
        "option command f7",
        "f1",
        "shift f6",
        "control option command w",
        "option shift up",
        "option down",
        "command backspace",
        "command forwarddelete",
        "control shift tab",
        "command space",
        "option return",
        "command escape",
        "command home",
        "command end",
        "command pageup",
        "command pagedown",
        "control left",
        "control right",
        "control shift `",
        "command +",
        "command -",
        "control command 0",
        "f20"
    ])
    func textRoundTrips(text: String) {
        #expect(KeyStroke(text: text)?.text == text)
    }

    @Test
    func parsingToleratesModifierOrderAndCase() {
        #expect(KeyStroke(text: "command option x")?.text == "option command x")
        #expect(KeyStroke(text: "Shift Command B") == nil)
        #expect(KeyStroke(text: "shift command B")?.text == "shift command b")
        #expect(KeyStroke(text: "command F12")?.text == "command f12")
        #expect(KeyStroke(text: "command Up")?.text == "command up")
    }

    @Test(arguments: ["", "   ", "bogus b", "command", "command ab", "meta b"])
    func invalidTextIsRejected(text: String) {
        #expect(KeyStroke(text: text) == nil)
    }

    @Test
    func displayTextUsesIntelliJGlyphs() {
        #expect(KeyStroke("b", .command).displayText == "\u{2318}B")
        #expect(KeyStroke(KeyNames.up, [.option, .shift]).displayText == "\u{2325}\u{21E7}\u{2191}")
        #expect(KeyStroke(KeyNames.f1).displayText == "F1")
        #expect(KeyStroke(KeyNames.f7, .option).displayText == "\u{2325}F7")
        #expect(KeyStroke(KeyNames.backspace, .command).displayText == "\u{2318}\u{232B}")
        #expect(KeyStroke(KeyNames.tab, [.control, .shift]).displayText == "\u{2303}\u{21E7}\u{21E5}")
        #expect(KeyStroke("[", [.shift, .command]).displayText == "\u{21E7}\u{2318}[")
        #expect(KeyStroke("p", .control).displayText == "\u{2303}P")
    }

    @Test
    func buildsTheSwiftUIKeyboardShortcut() {
        #expect(KeyStroke("k", .option).keyboardShortcut == KeyboardShortcut("k", modifiers: .option))
        #expect(
            KeyStroke(KeyNames.f7, [.option, .command]).keyboardShortcut
                == KeyboardShortcut(KeyEquivalent("\u{F70A}"), modifiers: [.option, .command])
        )
        #expect(
            KeyStroke(KeyNames.up, [.option, .shift]).keyboardShortcut
                == KeyboardShortcut(.upArrow, modifiers: [.option, .shift])
        )
        #expect(KeyStroke(KeyNames.tab, .option).keyboardShortcut == KeyboardShortcut(.tab, modifiers: .option))
        #expect(KeyStroke(KeyNames.backspace, .command).keyboardShortcut == KeyboardShortcut(.delete))
        #expect(KeyStroke(KeyNames.forwardDelete, .command).keyboardShortcut == KeyboardShortcut(.deleteForward))
        #expect(KeyStroke(KeyNames.space, .control).keyboardShortcut == KeyboardShortcut(.space, modifiers: .control))
        #expect(KeyStroke(KeyNames.enter, .option).keyboardShortcut == KeyboardShortcut(.return, modifiers: .option))
    }

    @Test
    func assignabilityRequiresAMenuModifierOrAFunctionKey() {
        #expect(!KeyStroke("b").isAssignable)
        #expect(!KeyStroke("b", .shift).isAssignable)
        #expect(KeyStroke("b", .option).isAssignable)
        #expect(KeyStroke("b", .control).isAssignable)
        #expect(KeyStroke("b", .command).isAssignable)
        #expect(KeyStroke(KeyNames.f1).isAssignable)
        #expect(KeyStroke(KeyNames.f12, .shift).isAssignable)
        #expect(!KeyStroke(KeyNames.up).isAssignable)
        #expect(!KeyStroke(KeyNames.up, .shift).isAssignable)
        #expect(KeyStroke(KeyNames.up, .command).isAssignable)
    }
}

@Suite
struct ShortcutTests {
    @Test
    func keyStrokeShortcutsExposeTheirStrokeAndText() {
        let shortcut = Shortcut.stroke("b", [.shift, .command])

        #expect(shortcut.keyStroke == KeyStroke("b", [.shift, .command]))
        #expect(shortcut.text == "shift command b")
        #expect(shortcut.displayText == "\u{21E7}\u{2318}B")
        #expect(Shortcut(text: "shift command b") == shortcut)
    }

    @Test
    func doubleModifierShortcutsHaveNoKeyStroke() {
        let shortcut = Shortcut.doubleModifier(.shift)

        #expect(shortcut.keyStroke == nil)
        #expect(shortcut.text == "double shift")
        #expect(shortcut.displayText == "\u{21E7}\u{21E7}")
        #expect(Shortcut(text: "double shift") == shortcut)
        #expect(Shortcut(text: "double command")?.displayText == "\u{2318}\u{2318}")
    }

    @Test(arguments: ["", "double", "double foo", "double shift shift", "meta b"])
    func invalidShortcutTextIsRejected(text: String) {
        #expect(Shortcut(text: text) == nil)
    }
}
