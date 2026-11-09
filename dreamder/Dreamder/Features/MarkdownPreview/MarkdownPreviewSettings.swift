import Foundation

extension SettingsData {
    struct MarkdownPreviewSettings: Codable, Hashable {
        static let fontSizeOptions = [8, 9, 10, 11, 12, 14, 16, 18, 20, 22, 24, 26, 28, 36, 48, 72]

        var isVerticalSplit: Bool = true
        var lastLayout: MarkdownPreviewLayout = .editorAndPreview
        var isAutoScrollEnabled: Bool = true
        var fontSize: Int?

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.isVerticalSplit = container.lenient(.isVerticalSplit, default: true)
            self.lastLayout = container.lenient(.lastLayout, default: .editorAndPreview)
            self.isAutoScrollEnabled = container.lenient(.isAutoScrollEnabled, default: true)
            self.fontSize = container.lenientOptional(.fontSize)
        }

        func resolvedFontSize(editorFontSize: Double) -> Int {
            fontSize ?? Int(editorFontSize.rounded())
        }
    }
}
