import AppKit
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct RecordedKeyTests {
    private func interpret(
        _ keyCode: UInt16,
        _ flags: NSEvent.ModifierFlags = [],
        characters: String? = nil
    ) -> RecordedKey {
        RecordedKey.interpret(keyCode: keyCode, characters: characters, flags: flags)
    }

    @Test
    func lettersWithModifiersAreRecorded() {
        #expect(interpret(11, .command) == .stroke(KeyStroke("b", .command)))
        #expect(interpret(11, [.command, .shift], characters: "B") == .stroke(KeyStroke("b", [.shift, .command])))
        #expect(interpret(37, [.option, .command]) == .stroke(KeyStroke("l", [.option, .command])))
        #expect(interpret(5, .control) == .stroke(KeyStroke("g", .control)))
    }

    @Test
    func digitsAndPunctuationUseThePhysicalKey() {
        #expect(interpret(18, .command) == .stroke(KeyStroke("1", .command)))
        #expect(interpret(29, .command) == .stroke(KeyStroke("0", .command)))
        #expect(interpret(33, [.shift, .command], characters: "{") == .stroke(KeyStroke("[", [.shift, .command])))
        #expect(interpret(30, .command) == .stroke(KeyStroke("]", .command)))
        #expect(interpret(44, [.option, .command]) == .stroke(KeyStroke("/", [.option, .command])))
        #expect(interpret(43, .command) == .stroke(KeyStroke(",", .command)))
        #expect(interpret(50, [.control, .shift]) == .stroke(KeyStroke("`", [.control, .shift])))
    }

    @Test
    func functionKeysAreRecordedWithAndWithoutModifiers() {
        #expect(interpret(122) == .stroke(KeyStroke(KeyNames.f1)))
        #expect(interpret(98, .option) == .stroke(KeyStroke(KeyNames.f7, .option)))
        #expect(interpret(111, [.shift, .command]) == .stroke(KeyStroke(KeyNames.f12, [.shift, .command])))
        #expect(interpret(97, .shift) == .stroke(KeyStroke(KeyNames.f6, .shift)))
        #expect(interpret(120, .command) == .stroke(KeyStroke(KeyNames.f2, .command)))
        #expect(interpret(90) == .stroke(KeyStroke(KeyNames.functionKeys[19])))
    }

    @Test
    func arrowsNeedAModifier() {
        #expect(interpret(126, [.option, .shift]) == .stroke(KeyStroke(KeyNames.up, [.option, .shift])))
        #expect(interpret(125, .option) == .stroke(KeyStroke(KeyNames.down, .option)))
        #expect(interpret(123, .control) == .stroke(KeyStroke(KeyNames.left, .control)))
        #expect(interpret(124, .command) == .stroke(KeyStroke(KeyNames.right, .command)))
        #expect(interpret(126) == .rejected(KeyStroke(KeyNames.up)))
        #expect(interpret(126, .shift) == .rejected(KeyStroke(KeyNames.up, .shift)))
    }

    @Test
    func navigationAndEditingKeysAreRecordedWithModifiers() {
        #expect(interpret(48, .option) == .stroke(KeyStroke(KeyNames.tab, .option)))
        #expect(interpret(36, .option) == .stroke(KeyStroke(KeyNames.enter, .option)))
        #expect(interpret(49, .control) == .stroke(KeyStroke(KeyNames.space, .control)))
        #expect(interpret(51, .command) == .stroke(KeyStroke(KeyNames.backspace, .command)))
        #expect(interpret(117, .command) == .stroke(KeyStroke(KeyNames.forwardDelete, .command)))
        #expect(interpret(115, .command) == .stroke(KeyStroke(KeyNames.home, .command)))
        #expect(interpret(119, .command) == .stroke(KeyStroke(KeyNames.end, .command)))
        #expect(interpret(116, .command) == .stroke(KeyStroke(KeyNames.pageUp, .command)))
        #expect(interpret(121, .command) == .stroke(KeyStroke(KeyNames.pageDown, .command)))
        #expect(interpret(53, .command) == .stroke(KeyStroke(KeyNames.escape, .command)))
    }

    @Test
    func plainAndShiftedPrintableKeysAreRejected() {
        #expect(interpret(11) == .rejected(KeyStroke("b")))
        #expect(interpret(11, .shift) == .rejected(KeyStroke("b", .shift)))
        #expect(interpret(49) == .rejected(KeyStroke(KeyNames.space)))
        #expect(interpret(36) == .rejected(KeyStroke(KeyNames.enter)))
    }

    @Test
    func escapeCancelsAndDeleteKeysClear() {
        #expect(interpret(53) == .cancel)
        #expect(interpret(51) == .clear)
        #expect(interpret(117) == .clear)
    }

    @Test
    func deviceFlagsOtherThanTheFourModifiersAreIgnored() {
        let flags: NSEvent.ModifierFlags = [.command, .capsLock, .function, .numericPad]

        #expect(interpret(126, flags) == .stroke(KeyStroke(KeyNames.up, .command)))
        #expect(interpret(53, [.capsLock]) == .cancel)
    }

    @Test
    func unknownKeyCodesFallBackToTheTypedCharacter() {
        #expect(interpret(0xFFF, .command, characters: "\u{436}") == .stroke(KeyStroke("\u{436}", .command)))
        #expect(interpret(0xFFF, .command, characters: "Q") == .stroke(KeyStroke("q", .command)))
        #expect(interpret(0xFFF, .command, characters: nil) == .unrecognized)
        #expect(interpret(0xFFF, .command, characters: "") == .unrecognized)
        #expect(interpret(0xFFF, .command, characters: "ab") == .unrecognized)
    }

    @Test
    func theCapturedStrokeBuildsTheMenuShortcut() throws {
        guard case .stroke(let stroke) = interpret(98, [.option, .command]) else {
            Issue.record("F7 was not recorded as a stroke")
            return
        }

        #expect(stroke.text == "option command f7")
        #expect(stroke.displayText == "\u{2325}\u{2318}F7")
    }

    @Test
    func aSynthesizedKeyDownEventParsesLikeTheRawFields() throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "B",
            charactersIgnoringModifiers: "b",
            isARepeat: false,
            keyCode: 11
        ))

        let key = RecordedKey.interpret(
            keyCode: event.keyCode,
            characters: event.charactersIgnoringModifiers,
            flags: event.modifierFlags
        )

        #expect(key == .stroke(KeyStroke("b", [.shift, .command])))
    }
}
