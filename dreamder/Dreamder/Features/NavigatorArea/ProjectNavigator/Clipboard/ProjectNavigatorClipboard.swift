import AppKit

@MainActor
struct ProjectNavigatorClipboard {
    let pasteboard: any PasteboardAccess

    var fileURLs: [URL] {
        pasteboard.fileURLs
    }

    var hasFiles: Bool {
        !fileURLs.isEmpty
    }

    var isCut: Bool {
        pasteboard.containsCutMarker
    }

    var text: String? {
        guard let text = pasteboard.plainText, !text.isEmpty else { return nil }
        return text
    }

    func write(_ urls: [URL], isCut: Bool) {
        pasteboard.replaceContents(withFiles: urls, isCut: isCut)
    }

    func clear() {
        pasteboard.removeAllContents()
    }
}
