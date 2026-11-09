import AppKit
import Foundation

extension CodeFileDocument {
    func reloadContentDiscardingEdits() {
        guard let url = fileURL, let type = fileType else { return }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        do {
            try read(from: url, ofType: type)
        } catch {
            return
        }
        fileModificationDate = attributes?[.modificationDate] as? Date
        updateChangeCount(.changeCleared)
    }
}

extension SourceControlManager {
    func reloadOpenDocuments(at urls: [URL]) {
        let targets = Set(urls.map(Self.canonicalPath))
        reloadOpenDocuments { targets.contains(Self.canonicalPath($0)) }
    }

    func reloadOpenDocuments(under directory: URL) {
        let prefix = Self.canonicalPath(directory) + "/"
        reloadOpenDocuments { Self.canonicalPath($0).hasPrefix(prefix) }
    }

    private func reloadOpenDocuments(matching isAffected: (URL) -> Bool) {
        for case let document as CodeFileDocument in NSDocumentController.shared.documents {
            guard let url = document.fileURL, isAffected(url) else { continue }
            document.reloadContentDiscardingEdits()
        }
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().path(percentEncoded: false).withoutTrailingSlashes
    }
}
