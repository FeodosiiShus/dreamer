import AppKit
import Foundation
import Testing
@testable import Dreamder

@Suite
struct CodeTextStorageCoverageTests {
    @Test
    func anEmptyStorageHasNoText() {
        let storage = CodeTextStorage()

        #expect(storage.string.isEmpty)
        #expect(storage.length == 0)
    }

    @Test
    func aStorageCopiesTheTextAndAttributesOfAnAttributedString() {
        let source = NSAttributedString(string: "abc", attributes: [.foregroundColor: NSColor.red])

        let storage = CodeTextStorage(attributedString: source)

        #expect(storage.string == "abc")
        #expect(storage.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor == .red)
    }

    @Test
    func aStorageCannotBeDecodedFromACoder() throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: "x", requiringSecureCoding: false)
        let coder = try NSKeyedUnarchiver(forReadingFrom: data)
        coder.requiresSecureCoding = false

        #expect(CodeTextStorage(coder: coder) == nil)
    }

    @Test
    func aStorageCannotBeCreatedFromAPasteboardPropertyList() {
        #expect(CodeTextStorage(pasteboardPropertyList: "text", ofType: .string) == nil)
    }
}
