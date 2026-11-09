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

    func unsavedOpenDocumentPaths(touchedBy urls: [URL]) -> [String] {
        openCodeFiles(touchedBy: urls)
            .filter { $0.document.isDocumentEdited }
            .map { DiffPath.relativePath(of: $0.url, from: repositoryURL) }
            .sorted()
    }

    func reloadUneditedOpenDocuments(touchedBy urls: [URL]) {
        for match in openCodeFiles(touchedBy: urls) where !match.document.isDocumentEdited {
            match.document.reloadContentDiscardingEdits()
        }
    }

    private func openCodeFiles(touchedBy urls: [URL]) -> [(document: CodeFileDocument, url: URL)] {
        let targets = urls.map(Self.canonicalPath)
        var matches: [(document: CodeFileDocument, url: URL)] = []
        for case let document as CodeFileDocument in NSDocumentController.shared.documents {
            guard let url = document.fileURL else { continue }
            let path = Self.canonicalPath(url)
            if targets.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                matches.append((document, url))
            }
        }
        return matches
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
