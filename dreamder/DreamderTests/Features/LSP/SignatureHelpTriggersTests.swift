import AppKit
import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite
struct SignatureHelpTriggersTests {
    private func units(_ text: String) -> [UInt16] {
        Array(text.utf16)
    }

    private func capability(
        staticOptions: SignatureHelpOptions? = SignatureHelpOptions(),
        registered: Bool = false,
        dynamic: [SignatureHelpOptions] = []
    ) -> SignatureHelpCapability? {
        SignatureHelpCapability(staticOptions: staticOptions, isDynamicallyRegistered: registered, dynamicOptions: dynamic)
    }

    @Test
    func noCapabilityWithoutAStaticProviderOrARegistration() {
        #expect(capability(staticOptions: nil) == nil)
        #expect(capability(staticOptions: nil, registered: true) != nil)
        #expect(capability(staticOptions: SignatureHelpOptions()) != nil)
    }

    @Test
    func serversDeclaringNoTriggerCharactersFallBackToParenAndComma() {
        let empty = capability(staticOptions: SignatureHelpOptions(triggerCharacters: []))
        let undeclared = capability(staticOptions: nil, registered: true)

        #expect(empty?.triggerCharacters == ["(", ","])
        #expect(undeclared?.triggerCharacters == ["(", ","])
        #expect(empty?.retriggerCharacters == [])
    }

    @Test
    func declaredTriggerAndRetriggerCharactersReplaceTheFallback() {
        let declared = capability(
            staticOptions: SignatureHelpOptions(triggerCharacters: ["<"], retriggerCharacters: [")"])
        )

        #expect(declared?.triggerCharacters == ["<"])
        #expect(declared?.retriggerCharacters == [")"])
    }

    @Test
    func dynamicRegistrationOptionsWinOverStaticOnes() {
        let merged = capability(
            staticOptions: SignatureHelpOptions(triggerCharacters: ["<"], retriggerCharacters: [")"]),
            registered: true,
            dynamic: [
                SignatureHelpOptions(triggerCharacters: nil, retriggerCharacters: nil),
                SignatureHelpOptions(triggerCharacters: ["!"], retriggerCharacters: [";"])
            ]
        )

        #expect(merged?.triggerCharacters == ["!"])
        #expect(merged?.retriggerCharacters == [";"])
    }

    @Test
    func dynamicRegistrationWithoutCharactersKeepsTheStaticOnes() {
        let kept = capability(
            staticOptions: SignatureHelpOptions(triggerCharacters: ["<"]),
            registered: true,
            dynamic: [SignatureHelpOptions()]
        )

        #expect(kept?.triggerCharacters == ["<"])
    }

    @Test
    func typedTriggerCharactersStartAFreshSignatureHelp() throws {
        let declared = try #require(capability(staticOptions: SignatureHelpOptions(retriggerCharacters: [")"])))
        let context = SignatureHelpTriggerPolicy.context(typed: "(", capability: declared, activeSignatureHelp: nil)

        #expect(context == .typed("(", activeSignatureHelp: nil))
        #expect(SignatureHelpTriggerPolicy.context(typed: "x", capability: declared, activeSignatureHelp: nil) == nil)
        #expect(SignatureHelpTriggerPolicy.context(typed: "()", capability: declared, activeSignatureHelp: nil) == nil)
        #expect(SignatureHelpTriggerPolicy.context(typed: "", capability: declared, activeSignatureHelp: nil) == nil)
        #expect(SignatureHelpTriggerPolicy.context(typed: ")", capability: declared, activeSignatureHelp: nil) == nil)
    }

    @Test
    func whileOpenTriggerAndRetriggerCharactersRetriggerWithTheActiveHelp() throws {
        let declared = try #require(capability(staticOptions: SignatureHelpOptions(retriggerCharacters: [")"])))
        let active = SignatureHelpFixtures.oneOverload()

        #expect(
            SignatureHelpTriggerPolicy.context(typed: ",", capability: declared, activeSignatureHelp: active)
                == .typed(",", activeSignatureHelp: active)
        )
        #expect(
            SignatureHelpTriggerPolicy.context(typed: ")", capability: declared, activeSignatureHelp: active)
                == .typed(")", activeSignatureHelp: active)
        )
        #expect(SignatureHelpTriggerPolicy.context(typed: "x", capability: declared, activeSignatureHelp: active) == nil)
    }

    @Test
    func enclosingOpenParenSkipsBalancedCalls() {
        let text = "foo(a, bar(b), "

        #expect(SignatureHelpCallRegion.enclosingOpenParen(before: text.utf16.count, in: units(text)) == 3)
        #expect(SignatureHelpCallRegion.enclosingOpenParen(before: 12, in: units(text)) == 10)
        #expect(SignatureHelpCallRegion.enclosingOpenParen(before: 99, in: units(text)) == 3)
        #expect(SignatureHelpCallRegion.enclosingOpenParen(before: 3, in: units(text)) == nil)
        #expect(SignatureHelpCallRegion.enclosingOpenParen(before: 4, in: units(text)) == 3)
        #expect(SignatureHelpCallRegion.enclosingOpenParen(before: 0, in: units(text)) == nil)
    }

    @Test
    func enclosingOpenParenIsNilAfterACompletedCall() {
        #expect(SignatureHelpCallRegion.enclosingOpenParen(before: 9, in: units("foo(a, b) ")) == nil)
        #expect(SignatureHelpCallRegion.enclosingOpenParen(before: 5, in: units("foo a")) == nil)
    }

    @Test
    func matchingCloseParenHandlesNestingAndMissingClosers() {
        let text = units("foo(a, bar(b), c) + (d")

        #expect(SignatureHelpCallRegion.matchingCloseParen(of: 3, in: text) == 16)
        #expect(SignatureHelpCallRegion.matchingCloseParen(of: 10, in: text) == 12)
        #expect(SignatureHelpCallRegion.matchingCloseParen(of: 20, in: text) == nil)
        #expect(SignatureHelpCallRegion.matchingCloseParen(of: 4, in: text) == nil)
        #expect(SignatureHelpCallRegion.matchingCloseParen(of: 99, in: text) == nil)
        #expect(SignatureHelpCallRegion.matchingCloseParen(of: -1, in: text) == nil)
    }

    @Test
    func callRegionContainsCaretsBetweenTheParens() {
        let text = units("foo(a, b) bar(c")

        #expect(SignatureHelpCallRegion.contains(caret: 4, openParen: 3, in: text))
        #expect(SignatureHelpCallRegion.contains(caret: 8, openParen: 3, in: text))
        #expect(!SignatureHelpCallRegion.contains(caret: 3, openParen: 3, in: text))
        #expect(!SignatureHelpCallRegion.contains(caret: 9, openParen: 3, in: text))
        #expect(!SignatureHelpCallRegion.contains(caret: 10, openParen: 3, in: text))
        #expect(SignatureHelpCallRegion.contains(caret: 15, openParen: 13, in: text))
        #expect(!SignatureHelpCallRegion.contains(caret: 5, openParen: 4, in: text))
        #expect(!SignatureHelpCallRegion.contains(caret: 5, openParen: 99, in: text))
    }

    @Test
    func editsShiftTheOpenParenOrInvalidateIt() {
        #expect(SignatureHelpCallRegion.shifted(openParen: 10, forEditIn: NSRange(location: 11, length: 0), replacementLength: 4) == 10)
        #expect(SignatureHelpCallRegion.shifted(openParen: 10, forEditIn: NSRange(location: 2, length: 0), replacementLength: 3) == 13)
        #expect(SignatureHelpCallRegion.shifted(openParen: 10, forEditIn: NSRange(location: 10, length: 0), replacementLength: 1) == 11)
        #expect(SignatureHelpCallRegion.shifted(openParen: 10, forEditIn: NSRange(location: 4, length: 6), replacementLength: 1) == 5)
        #expect(SignatureHelpCallRegion.shifted(openParen: 10, forEditIn: NSRange(location: 10, length: 1), replacementLength: 1) == nil)
        #expect(SignatureHelpCallRegion.shifted(openParen: 10, forEditIn: NSRange(location: 8, length: 5), replacementLength: 0) == nil)
    }

    @Test
    func positionsCountLinesAndUtf16Columns() {
        let text = units("ab\ncd😀\n\nxyz")

        #expect(SignatureHelpCallRegion.position(ofOffset: 0, in: text) == Position(line: 0, character: 0))
        #expect(SignatureHelpCallRegion.position(ofOffset: 2, in: text) == Position(line: 0, character: 2))
        #expect(SignatureHelpCallRegion.position(ofOffset: 3, in: text) == Position(line: 1, character: 0))
        #expect(SignatureHelpCallRegion.position(ofOffset: 7, in: text) == Position(line: 1, character: 4))
        #expect(SignatureHelpCallRegion.position(ofOffset: 9, in: text) == Position(line: 3, character: 0))
        #expect(SignatureHelpCallRegion.position(ofOffset: 99, in: text) == Position(line: 3, character: 3))
        #expect(SignatureHelpCallRegion.position(ofOffset: -4, in: text) == Position(line: 0, character: 0))
    }

    @Test
    func keyActionsFollowEscapeAndTheArrowKeys() {
        let arrowFlags: NSEvent.ModifierFlags = [.function, .numericPad]

        #expect(SignatureHelpKeyAction.resolve(keyCode: 53, modifiers: [], signatureCount: 1) == .dismiss)
        #expect(SignatureHelpKeyAction.resolve(keyCode: 53, modifiers: [.shift], signatureCount: 3) == nil)
        #expect(SignatureHelpKeyAction.resolve(keyCode: 126, modifiers: arrowFlags, signatureCount: 2) == .previousSignature)
        #expect(SignatureHelpKeyAction.resolve(keyCode: 125, modifiers: arrowFlags, signatureCount: 2) == .nextSignature)
        #expect(SignatureHelpKeyAction.resolve(keyCode: 126, modifiers: [.option], signatureCount: 2) == .previousSignature)
        #expect(SignatureHelpKeyAction.resolve(keyCode: 125, modifiers: [.option, .function], signatureCount: 2) == .nextSignature)
    }

    @Test
    func arrowKeysPassThroughWithOneSignatureOrOtherModifiers() {
        #expect(SignatureHelpKeyAction.resolve(keyCode: 126, modifiers: [], signatureCount: 1) == nil)
        #expect(SignatureHelpKeyAction.resolve(keyCode: 125, modifiers: [], signatureCount: 0) == nil)
        #expect(SignatureHelpKeyAction.resolve(keyCode: 126, modifiers: [.command], signatureCount: 3) == nil)
        #expect(SignatureHelpKeyAction.resolve(keyCode: 125, modifiers: [.shift], signatureCount: 3) == nil)
        #expect(SignatureHelpKeyAction.resolve(keyCode: 125, modifiers: [.option, .shift], signatureCount: 3) == nil)
        #expect(SignatureHelpKeyAction.resolve(keyCode: 0, modifiers: [], signatureCount: 3) == nil)
    }

    @Test
    func popupGoesAboveTheCaretWhenThereIsNoScreen() {
        let size = NSSize(width: 300, height: 60)
        let anchor = NSRect(x: 100, y: 500, width: 2, height: 16)
        let frame = SignatureHelpPlacement.frame(size: size, anchor: anchor, visibleFrame: nil)

        #expect(frame == NSRect(x: 100, y: 520, width: 300, height: 60))
    }

    @Test
    func popupStaysAboveWhenItFits() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let frame = SignatureHelpPlacement.frame(
            size: NSSize(width: 300, height: 60),
            anchor: NSRect(x: 100, y: 500, width: 2, height: 16),
            visibleFrame: visible
        )

        #expect(frame.minY == 520)
        #expect(frame.minX == 100)
    }

    @Test
    func popupMovesBelowOnlyWhenAboveDoesNotFit() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let frame = SignatureHelpPlacement.frame(
            size: NSSize(width: 300, height: 100),
            anchor: NSRect(x: 100, y: 720, width: 2, height: 16),
            visibleFrame: visible
        )

        #expect(frame.maxY <= 720 - SignatureHelpPlacement.gap)
        #expect(frame.minY == 720 - 100 - SignatureHelpPlacement.gap)
    }

    @Test
    func popupPicksTheRoomierSideWhenNeitherFitsAndClampsIntoTheScreen() {
        let visible = NSRect(x: 0, y: 0, width: 400, height: 200)
        let size = NSSize(width: 300, height: 150)
        let nearTop = SignatureHelpPlacement.frame(
            size: size,
            anchor: NSRect(x: 380, y: 120, width: 2, height: 16),
            visibleFrame: visible
        )
        let nearBottom = SignatureHelpPlacement.frame(
            size: size,
            anchor: NSRect(x: -50, y: 70, width: 2, height: 16),
            visibleFrame: visible
        )

        #expect(nearTop.minX == visible.maxX - size.width - SignatureHelpPlacement.screenMargin)
        #expect(nearTop.minY == visible.minY + SignatureHelpPlacement.screenMargin)
        #expect(nearBottom.minX == visible.minX + SignatureHelpPlacement.screenMargin)
        #expect(nearBottom.maxY == visible.maxY - SignatureHelpPlacement.screenMargin)
    }
}
