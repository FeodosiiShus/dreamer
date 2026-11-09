import AppKit
import Testing
@testable import Dreamder

@MainActor
private final class FakePasteboardBoard: PasteboardStoring {
    private(set) var items: [NSPasteboardItem] = []
    private(set) var strings: [NSPasteboard.PasteboardType: String] = [:]
    private(set) var clearCount = 0

    var pasteboardItems: [NSPasteboardItem]? {
        items.isEmpty ? nil : items
    }

    func clearContents() -> Int {
        items = []
        strings = [:]
        clearCount += 1
        return clearCount
    }

    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        strings[dataType] = string
        return true
    }

    func string(forType dataType: NSPasteboard.PasteboardType) -> String? {
        strings[dataType]
    }

    func canReadItem(withDataConformingToTypes types: [String]) -> Bool {
        types.contains { strings[NSPasteboard.PasteboardType($0)] != nil }
    }

    func readObjects(forClasses classArray: [AnyClass], options: [NSPasteboard.ReadingOptionKey: Any]?) -> [Any]? {
        let urls = items
            .compactMap { $0.string(forType: .fileURL) }
            .compactMap { URL(string: $0) }
            .map { $0 as NSURL }
        return urls.isEmpty ? nil : urls
    }

    func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool {
        items = objects.compactMap { $0 as? NSPasteboardItem }
        return true
    }
}

@MainActor
@Suite(.uiGate)
struct SystemPasteboardTests {
    private let first = URL(fileURLWithPath: "/tmp/dreamder-first.txt")
    private let second = URL(fileURLWithPath: "/tmp/dreamder-second.txt")

    @Test
    func anEmptyBoardHasNoTextAndNoFiles() {
        let pasteboard = SystemPasteboard(board: FakePasteboardBoard())

        #expect(pasteboard.plainText == nil)
        #expect(!pasteboard.canReadPlainText)
        #expect(pasteboard.fileURLs.isEmpty)
        #expect(!pasteboard.containsCutMarker)
    }

    @Test
    func textReplacesTheContentsAndCanBeRead() {
        let board = FakePasteboardBoard()
        let pasteboard = SystemPasteboard(board: board)

        pasteboard.replaceContents(withText: "hello")
        pasteboard.replaceContents(withText: "world")

        #expect(pasteboard.plainText == "world")
        #expect(pasteboard.canReadPlainText)
        #expect(board.clearCount == 2)
    }

    @Test
    func copiedFilesAreReadBackWithoutACutMarker() {
        let board = FakePasteboardBoard()
        let pasteboard = SystemPasteboard(board: board)
        pasteboard.replaceContents(withText: "stale")

        pasteboard.replaceContents(withFiles: [first, second], isCut: false)

        #expect(pasteboard.fileURLs == [first, second])
        #expect(!pasteboard.containsCutMarker)
        #expect(pasteboard.plainText == nil)
    }

    @Test
    func cutFilesMarkOnlyTheFirstItem() {
        let board = FakePasteboardBoard()
        let pasteboard = SystemPasteboard(board: board)

        pasteboard.replaceContents(withFiles: [first, second], isCut: true)

        #expect(pasteboard.fileURLs == [first, second])
        #expect(pasteboard.containsCutMarker)
        #expect(board.items.map { $0.types.contains(SystemPasteboard.cutMarkerType) } == [true, false])
    }

    @Test
    func removingAllContentsClearsTextFilesAndTheCutMarker() {
        let pasteboard = SystemPasteboard(board: FakePasteboardBoard())
        pasteboard.replaceContents(withFiles: [first], isCut: true)

        pasteboard.removeAllContents()

        #expect(pasteboard.fileURLs.isEmpty)
        #expect(!pasteboard.containsCutMarker)
        #expect(pasteboard.plainText == nil)
    }
}
