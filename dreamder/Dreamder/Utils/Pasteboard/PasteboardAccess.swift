import AppKit

@MainActor
protocol PasteboardAccess: AnyObject {
    var plainText: String? { get }
    var canReadPlainText: Bool { get }
    var fileURLs: [URL] { get }
    var containsCutMarker: Bool { get }

    func replaceContents(withText text: String)
    func replaceContents(withFiles urls: [URL], isCut: Bool)
    func removeAllContents()
}

@MainActor
protocol PasteboardStoring: AnyObject {
    var pasteboardItems: [NSPasteboardItem]? { get }

    @discardableResult func clearContents() -> Int
    @discardableResult func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool
    func string(forType dataType: NSPasteboard.PasteboardType) -> String?
    func canReadItem(withDataConformingToTypes types: [String]) -> Bool
    func readObjects(forClasses classArray: [AnyClass], options: [NSPasteboard.ReadingOptionKey: Any]?) -> [Any]?
    func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool
}

extension NSPasteboard: PasteboardStoring {}

@MainActor
final class SystemPasteboard: PasteboardAccess {
    static let cutMarkerType = NSPasteboard.PasteboardType("dev.dreamder.projectNavigator.cut")

    private let injectedBoard: (any PasteboardStoring)?

    init(board: (any PasteboardStoring)? = nil) {
        injectedBoard = board
    }

    private var board: any PasteboardStoring { injectedBoard ?? NSPasteboard.general }

    var plainText: String? {
        board.string(forType: .string)
    }

    var canReadPlainText: Bool {
        board.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.string.rawValue])
    }

    var fileURLs: [URL] {
        let objects = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        return objects?.compactMap { $0 as? URL } ?? []
    }

    var containsCutMarker: Bool {
        board.pasteboardItems?.contains { $0.types.contains(Self.cutMarkerType) } ?? false
    }

    func replaceContents(withText text: String) {
        board.clearContents()
        board.setString(text, forType: .string)
    }

    func replaceContents(withFiles urls: [URL], isCut: Bool) {
        let items = urls.enumerated().map { index, url -> NSPasteboardItem in
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            if isCut, index == 0 {
                item.setData(Data(), forType: Self.cutMarkerType)
            }
            return item
        }
        board.clearContents()
        _ = board.writeObjects(items)
    }

    func removeAllContents() {
        board.clearContents()
    }
}
