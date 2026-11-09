import AppKit
import CodeEditTextView
import Foundation
import LanguageServerProtocol
import Testing
import ZIPFoundation
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct SemanticTokenPositionTests {
    @Test
    func startPositionUsesLineAndCharacter() {
        let token = SemanticToken(line: 4, char: 7, length: 3, type: 0, modifiers: 0)

        #expect(token.startPosition == Position(line: 4, character: 7))
    }

    @Test
    func endPositionAddsTheLengthToTheCharacter() {
        let token = SemanticToken(line: 4, char: 7, length: 3, type: 0, modifiers: 0)

        #expect(token.endPosition == Position(line: 4, character: 10))
    }

    @Test
    func zeroLengthTokensStartWhereTheyEnd() {
        let token = SemanticToken(line: 0, char: 2, length: 0, type: 1, modifiers: 1)

        #expect(token.startPosition == token.endPosition)
    }
}

@MainActor
@Suite(.uiGate)
struct TextViewLSPRangeTests {
    private let text = "ab\ncd\nef"

    @Test
    func rangeInsideTheDocumentMapsToLineAndCharacter() throws {
        let textView = TextView(string: text)

        let range = try #require(textView.lspRangeFrom(nsRange: NSRange(location: 4, length: 3)))

        #expect(range.start == Position(line: 1, character: 1))
        #expect(range.end == Position(line: 2, character: 1))
    }

    @Test
    func rangeStartingAtTheDocumentStartHasLineZero() throws {
        let textView = TextView(string: text)

        let range = try #require(textView.lspRangeFrom(nsRange: NSRange(location: 0, length: 2)))

        #expect(range.start == Position(line: 0, character: 0))
        #expect(range.end == Position(line: 0, character: 2))
    }

    @Test
    func rangeEndingAtTheDocumentEndUsesTheLastLine() throws {
        let textView = TextView(string: text)

        let range = try #require(textView.lspRangeFrom(nsRange: NSRange(location: 0, length: text.utf16.count)))

        #expect(range.start == Position(line: 0, character: 0))
        #expect(range.end == Position(line: 2, character: 2))
    }

    @Test
    func rangeOutsideTheDocumentIsNil() {
        let textView = TextView(string: text)

        #expect(textView.lspRangeFrom(nsRange: NSRange(location: 50, length: 0)) == nil)
        #expect(textView.lspRangeFrom(nsRange: NSRange(location: 0, length: 50)) == nil)
    }
}

@MainActor
@Suite(.uiGate)
struct TextViewSemanticTokenRangeProviderTests {
    private let text = "ab\ncd\nef"

    @Test
    func lineCharAndLengthMapToAnNSRange() {
        let textView = TextView(string: text)

        #expect(textView.nsRangeFrom(line: 0, char: 1, length: 1) == NSRange(location: 1, length: 1))
        #expect(textView.nsRangeFrom(line: 1, char: 0, length: 2) == NSRange(location: 3, length: 2))
        #expect(textView.nsRangeFrom(line: 2, char: 1, length: 1) == NSRange(location: 7, length: 1))
    }

    @Test
    func semanticTokenRangeDelegatesToTheLineBasedOverload() {
        let textView = TextView(string: text)
        let range = SemanticTokenRange(line: 1, char: 1, length: 1)

        #expect(textView.nsRangeFrom(range) == NSRange(location: 4, length: 1))
    }

    @Test
    func lineBeyondTheDocumentIsNil() {
        let textView = TextView(string: text)

        #expect(textView.nsRangeFrom(line: 3, char: 0, length: 1) == nil)
        #expect(textView.nsRangeFrom(SemanticTokenRange(line: 99, char: 0, length: 1)) == nil)
    }
}

@MainActor
@Suite(.uiGate)
struct ZipFoundationErrorDescriptionTests {
    private static let descriptions: [(Archive.ArchiveError, String)] = [
        (.unreadableArchive, "Unreadable archive."),
        (.unwritableArchive, "Unwritable archive."),
        (.invalidEntryPath, "Invalid entry path."),
        (.invalidCompressionMethod, "Invalid compression method."),
        (.invalidCRC32, "Invalid checksum."),
        (.cancelledOperation, "Operation cancelled."),
        (.invalidBufferSize, "Invalid buffer size."),
        (.invalidEntrySize, "Invalid entry size."),
        (.invalidLocalHeaderDataOffset, "Invalid file detected."),
        (.invalidLocalHeaderSize, "Invalid file detected."),
        (.invalidCentralDirectoryOffset, "Invalid file detected."),
        (.invalidCentralDirectorySize, "Invalid file detected."),
        (.invalidCentralDirectoryEntryCount, "Invalid file detected."),
        (.missingEndOfCentralDirectoryRecord, "Invalid file detected."),
        (.uncontainedSymlink, "Uncontained symlink detected.")
    ]

    private static let failureReasons: [(Archive.ArchiveError, String)] = [
        (.invalidLocalHeaderDataOffset, "Invalid local header data offset."),
        (.invalidLocalHeaderSize, "Invalid local header size."),
        (.invalidCentralDirectoryOffset, "Invalid central directory offset."),
        (.invalidCentralDirectorySize, "Invalid central directory size."),
        (.invalidCentralDirectoryEntryCount, "Invalid central directory entry count."),
        (.missingEndOfCentralDirectoryRecord, "Missing end of central directory record.")
    ]

    @Test
    func everyCaseHasAHumanReadableDescription() {
        for (error, expected) in Self.descriptions {
            #expect(error.errorDescription == expected)
            #expect(error.localizedDescription == expected)
        }
    }

    @Test
    func structuralCasesExplainTheFailureReason() {
        for (error, expected) in Self.failureReasons {
            #expect(error.failureReason == expected)
        }
    }

    @Test
    func otherCasesHaveNoFailureReason() {
        let withReason = Set(Self.failureReasons.map { "\($0.0)" })
        for (error, _) in Self.descriptions where !withReason.contains("\(error)") {
            #expect(error.failureReason == nil)
        }
    }
}
