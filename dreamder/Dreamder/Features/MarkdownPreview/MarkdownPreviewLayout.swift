import AppKit
import Foundation
import SwiftUI

enum MarkdownPreviewLayout: String, CaseIterable, Identifiable {
    case editorOnly
    case editorAndPreview
    case previewOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .editorOnly: return "Editor Only"
        case .editorAndPreview: return "Editor and Preview"
        case .previewOnly: return "Preview Only"
        }
    }

    var iconName: String {
        switch self {
        case .editorOnly: return "general/editorOnly"
        case .editorAndPreview: return "general/editorPreview"
        case .previewOnly: return "general/previewOnly"
        }
    }

    var symbolName: String {
        switch self {
        case .editorOnly: return "rectangle"
        case .editorAndPreview: return "rectangle.split.2x1"
        case .previewOnly: return "eye"
        }
    }

    var icon: Image {
        if IntelliJIcon.nsImage(iconName) == nil {
            return Image(systemName: symbolName)
        }
        return Image(iconName)
    }
}

final class MarkdownPreviewLayoutStore: ObservableObject {
    static let shared = MarkdownPreviewLayoutStore()

    static let defaultLayout: MarkdownPreviewLayout = .editorAndPreview
    static let keyPrefix = "markdownPreviewLayout."
    static let markdownExtensions: Set<String> = ["md", "markdown"]

    @Published private(set) var layouts: [String: MarkdownPreviewLayout] = [:]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func isMarkdownFile(_ url: URL?) -> Bool {
        guard let url else { return false }
        return markdownExtensions.contains(url.pathExtension.lowercased())
    }

    static func key(for url: URL) -> String {
        keyPrefix + url.standardizedFileURL.path
    }

    func layout(for url: URL?) -> MarkdownPreviewLayout {
        guard let url else { return Self.defaultLayout }
        let key = Self.key(for: url)
        if let cached = layouts[key] {
            return cached
        }
        guard let stored = defaults.string(forKey: key),
              let layout = MarkdownPreviewLayout(rawValue: stored) else {
            return Self.defaultLayout
        }
        return layout
    }

    func setLayout(_ layout: MarkdownPreviewLayout, for url: URL?) {
        guard let url else { return }
        let key = Self.key(for: url)
        defaults.set(layout.rawValue, forKey: key)
        layouts[key] = layout
    }
}
