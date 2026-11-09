import Foundation
import LanguageServerProtocol

enum FoldRegionLoader {
    static func load(
        text: String,
        tabWidth: Int,
        client: LanguageServer<CodeFileDocument>?,
        uri: String?
    ) async -> [FoldRegion] {
        var serverRanges: [FoldingRange]?
        if let client, let uri, client.supportsFoldingRange {
            serverRanges = try? await client.requestFoldingRange(for: uri)
        }
        return await FoldRegionResolver.regions(serverRanges: serverRanges, text: text, tabWidth: tabWidth)
    }
}
