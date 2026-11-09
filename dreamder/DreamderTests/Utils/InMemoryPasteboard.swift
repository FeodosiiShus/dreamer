import AppKit
@testable import Dreamder

@MainActor
final class InMemoryPasteboard: PasteboardAccess, PasteboardStoring {
    private(set) var plainText: String?
    private(set) var fileURLs: [URL] = []
    private(set) var containsCutMarker = false
    private(set) var textWrites: [String] = []

    var canReadPlainText: Bool {
        plainText != nil
    }

    func replaceContents(withText text: String) {
        removeAllContents()
        plainText = text
        textWrites.append(text)
    }

    func replaceContents(withFiles urls: [URL], isCut: Bool) {
        removeAllContents()
        fileURLs = urls
        containsCutMarker = isCut && !urls.isEmpty
    }

    func removeAllContents() {
        plainText = nil
        fileURLs = []
        containsCutMarker = false
    }

    private var clearCount = 0

    var pasteboardItems: [NSPasteboardItem]? {
        guard !fileURLs.isEmpty else { return nil }
        return fileURLs.enumerated().map { index, url in
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            if containsCutMarker, index == 0 {
                item.setData(Data(), forType: SystemPasteboard.cutMarkerType)
            }
            return item
        }
    }

    func clearContents() -> Int {
        removeAllContents()
        clearCount += 1
        return clearCount
    }

    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        guard dataType == .string else { return false }
        plainText = string
        textWrites.append(string)
        return true
    }

    func string(forType dataType: NSPasteboard.PasteboardType) -> String? {
        dataType == .string ? plainText : nil
    }

    func canReadItem(withDataConformingToTypes types: [String]) -> Bool {
        plainText != nil && types.contains(NSPasteboard.PasteboardType.string.rawValue)
    }

    func readObjects(forClasses classArray: [AnyClass], options: [NSPasteboard.ReadingOptionKey: Any]?) -> [Any]? {
        fileURLs.isEmpty ? nil : fileURLs.map { $0 as NSURL }
    }

    func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool {
        let items = objects.compactMap { $0 as? NSPasteboardItem }
        fileURLs = items.compactMap { $0.string(forType: .fileURL) }.compactMap { URL(string: $0) }
        containsCutMarker = items.first?.types.contains(SystemPasteboard.cutMarkerType) == true
        return true
    }
}
