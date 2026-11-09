import AppKit
import Foundation
import SwiftUI

nonisolated enum MarkdownPreviewLayout: String, CaseIterable, Identifiable, Codable, Sendable {
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

    func iconName(isVerticalSplit: Bool) -> String {
        switch self {
        case .editorOnly: return "general/editorOnly"
        case .editorAndPreview: return isVerticalSplit ? "general/editorPreview" : "general/editorPreviewVertical"
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
}

extension MarkdownPreviewLayout {
    func icon(isVerticalSplit: Bool, hasCatalogIcon: (String) -> Bool = { IntelliJIcon.nsImage($0) != nil }) -> Image {
        let name = iconName(isVerticalSplit: isVerticalSplit)
        if !hasCatalogIcon(name) {
            return Image(systemName: symbolName)
        }
        return Image(name)
    }
}

protocol MarkdownPreviewStateStorage: AnyObject {
    func markdownPreviewState(for key: WorkspaceStateKey) -> Any?
    func storeMarkdownPreviewState(_ value: Any?, for key: WorkspaceStateKey)
}

extension WorkspaceDocument: MarkdownPreviewStateStorage {
    func markdownPreviewState(for key: WorkspaceStateKey) -> Any? {
        getFromWorkspaceState(key)
    }

    func storeMarkdownPreviewState(_ value: Any?, for key: WorkspaceStateKey) {
        addToWorkspaceState(key: key, value: value)
    }
}

@Observable
final class MarkdownPreviewLayoutStore {
    nonisolated static let defaultLayout: MarkdownPreviewLayout = .editorAndPreview
    nonisolated static let defaultSplitWeights: [CGFloat] = [0.5, 0.5]
    nonisolated static let markdownExtensions: Set<String> = ["md", "markdown"]

    private static let stores = NSMapTable<WorkspaceDocument, MarkdownPreviewLayoutStore>(
        keyOptions: .weakMemory,
        valueOptions: .strongMemory
    )

    static func store(
        for workspace: WorkspaceDocument,
        settings: Settings = .shared
    ) -> MarkdownPreviewLayoutStore {
        if let existing = stores.object(forKey: workspace) {
            return existing
        }
        let store = MarkdownPreviewLayoutStore(storage: workspace, settings: settings)
        stores.setObject(store, forKey: workspace)
        return store
    }

    nonisolated static func isMarkdownFile(_ url: URL?) -> Bool {
        guard let url else { return false }
        return markdownExtensions.contains(url.pathExtension.lowercased())
    }

    nonisolated static func key(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private(set) var fileLayouts: [String: MarkdownPreviewLayout]
    private(set) var forcedLayouts: [String: MarkdownPreviewLayout] = [:]
    private(set) var sessionOrientations: [String: Bool] = [:]

    var splitWeights: [CGFloat] {
        didSet {
            guard splitWeights != oldValue else { return }
            storage?.storeMarkdownPreviewState(splitWeights.map { Double($0) }, for: .markdownPreviewSplitWeights)
        }
    }

    @ObservationIgnored private let storage: MarkdownPreviewStateStorage?
    @ObservationIgnored private let settings: Settings

    init(storage: MarkdownPreviewStateStorage?, settings: Settings = .shared) {
        self.storage = storage
        self.settings = settings
        self.fileLayouts = Self.storedLayouts(storage?.markdownPreviewState(for: .markdownPreviewLayouts))
        self.splitWeights = Self.storedWeights(storage?.markdownPreviewState(for: .markdownPreviewSplitWeights))
    }

    private static func storedLayouts(_ stored: Any?) -> [String: MarkdownPreviewLayout] {
        guard let raw = stored as? [String: String] else { return [:] }
        return raw.compactMapValues { MarkdownPreviewLayout(rawValue: $0) }
    }

    private static func storedWeights(_ stored: Any?) -> [CGFloat] {
        guard let raw = stored as? [Double],
              raw.count == defaultSplitWeights.count,
              raw.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            return defaultSplitWeights
        }
        let total = raw.reduce(0, +)
        return raw.map { CGFloat($0 / total) }
    }

    var isVerticalSplit: Bool {
        settings.preferences.markdownPreview.isVerticalSplit
    }

    var isAutoScrollEnabled: Bool {
        settings.preferences.markdownPreview.isAutoScrollEnabled
    }

    var lastUsedLayout: MarkdownPreviewLayout {
        settings.preferences.markdownPreview.lastLayout
    }

    func setVerticalSplit(_ isVerticalSplit: Bool) {
        settings.preferences.markdownPreview.isVerticalSplit = isVerticalSplit
        sessionOrientations.removeAll()
    }

    func isVerticalSplit(for url: URL?) -> Bool {
        guard let url, let session = sessionOrientations[Self.key(for: url)] else { return isVerticalSplit }
        return session
    }

    func splitAxis(for url: URL?) -> Axis {
        isVerticalSplit(for: url) ? .horizontal : .vertical
    }

    func toggleOrientation(for url: URL?) {
        guard let url else { return }
        sessionOrientations[Self.key(for: url)] = !isVerticalSplit(for: url)
    }

    func layout(for url: URL?) -> MarkdownPreviewLayout {
        guard let url else { return lastUsedLayout }
        let key = Self.key(for: url)
        return forcedLayouts[key] ?? fileLayouts[key] ?? lastUsedLayout
    }

    func didOpen(_ url: URL?, isDocumentEmpty: Bool) {
        guard let url else { return }
        let key = Self.key(for: url)
        if isDocumentEmpty {
            forcedLayouts[key] = .editorOnly
        } else {
            forcedLayouts.removeValue(forKey: key)
        }
    }

    func setLayout(_ layout: MarkdownPreviewLayout, for url: URL?) {
        guard let url else { return }
        let key = Self.key(for: url)
        forcedLayouts.removeValue(forKey: key)
        fileLayouts[key] = layout
        storage?.storeMarkdownPreviewState(fileLayouts.mapValues(\.rawValue), for: .markdownPreviewLayouts)
        settings.preferences.markdownPreview.lastLayout = layout
    }

    func select(_ layout: MarkdownPreviewLayout, for url: URL?) {
        guard url != nil else { return }
        if self.layout(for: url) == layout {
            if layout == .editorAndPreview {
                toggleOrientation(for: url)
            }
            return
        }
        setLayout(layout, for: url)
    }
}
