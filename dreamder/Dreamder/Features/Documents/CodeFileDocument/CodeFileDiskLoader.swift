import Foundation

nonisolated struct CodeFileLoadedContent: Sendable {
    let content: CodeFileContentLoad
    let detectedIndent: DetectedIndent?
}

nonisolated enum CodeFileDiskLoader {
    typealias Loader = @Sendable (URL, String) async throws -> CodeFileLoadedContent

    static let live: Loader = { url, fileTypeName in
        try await read(from: url, fileTypeName: fileTypeName)
    }

    static func classify(data: Data, fileTypeName: String) -> CodeFileLoadedContent {
        let content = CodeFileContentLoad.classify(data: data, fileTypeName: fileTypeName)
        let detectedIndent = content.state.isReadOnly ? nil : content.text.flatMap { IndentDetector.detect(in: $0) }
        return CodeFileLoadedContent(content: content, detectedIndent: detectedIndent)
    }

    @concurrent
    static func read(from url: URL, fileTypeName: String) async throws -> CodeFileLoadedContent {
        try Task.checkCancellation()
        let data = try Data(contentsOf: url)
        try Task.checkCancellation()
        return classify(data: data, fileTypeName: fileTypeName)
    }
}
