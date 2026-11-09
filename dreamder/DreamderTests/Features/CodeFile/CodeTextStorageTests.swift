import AppKit
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct CodeTextStorageTests {
    @MainActor
    private final class EditRecorder: NSObject, NSTextStorageDelegate {
        var edits: [(mask: NSTextStorageEditActions, range: NSRange, delta: Int)] = []

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            edits.append((editedMask, editedRange, delta))
        }
    }

    @Test
    func attributesBeyondTheEndAreClampedInsteadOfThrowing() {
        let storage = CodeTextStorage(string: "short")
        storage.setAttributes([.foregroundColor: NSColor.red], range: NSRange(location: 3, length: 40))
        storage.setAttributes([.foregroundColor: NSColor.blue], range: NSRange(location: 20, length: 5))

        let colored = storage.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor
        let plain = storage.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor
        #expect(colored == .red)
        #expect(plain == nil)
        #expect(storage.string == "short")
    }

    @Test
    func addingAttributesPastTheEndTerminates() {
        let storage = CodeTextStorage(string: "ab")
        storage.addAttributes([.foregroundColor: NSColor.green], range: NSRange(location: 1, length: 10))

        let last = storage.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor
        #expect(last == .green)
        #expect(storage.length == 2)
    }

    @Test
    func replacementsOutsideTheTextAreIgnoredAndInsideOnesApply() {
        let storage = CodeTextStorage(string: "hello")
        storage.replaceCharacters(in: NSRange(location: 9, length: 2), with: "x")
        #expect(storage.string == "hello")

        storage.replaceCharacters(in: NSRange(location: 5, length: 0), with: " world")
        #expect(storage.string == "hello world")

        storage.replaceCharacters(in: NSRange(location: 0, length: 5), with: "bye")
        #expect(storage.string == "bye world")
    }

    @Test
    func editsAreReportedToTheDelegateWithTheAppliedRange() {
        let storage = CodeTextStorage(string: "abcdef")
        let recorder = EditRecorder()
        storage.delegate = recorder

        storage.replaceCharacters(in: NSRange(location: 2, length: 2), with: "XYZ")
        storage.setAttributes([.foregroundColor: NSColor.red], range: NSRange(location: 4, length: 50))

        #expect(recorder.edits.count == 2)
        #expect(recorder.edits.first?.range == NSRange(location: 2, length: 3))
        #expect(recorder.edits.first?.delta == 1)
        #expect(recorder.edits.last?.range == NSRange(location: 4, length: 3))
        #expect(recorder.edits.last?.mask.contains(.editedAttributes) == true)
    }

    @Test
    func documentsReadIntoTheClampingStorage() throws {
        try withTempDir { directory in
            let url = directory.appending(path: "Notes.txt")
            try "text\n".write(to: url, atomically: true, encoding: .utf8)
            let document = try CodeFileDocument(for: url, withContentsOf: url, ofType: "public.plain-text")

            #expect(document.content is CodeTextStorage)
        }
    }
}
