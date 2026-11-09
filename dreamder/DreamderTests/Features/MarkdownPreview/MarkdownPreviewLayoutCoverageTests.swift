import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct MarkdownPreviewLayoutCoverageTests {
    private let file = URL(fileURLWithPath: "/tmp/notes/README.md")

    @Test
    func everyLayoutHasAFallbackSymbol() {
        #expect(MarkdownPreviewLayout.editorOnly.symbolName == "rectangle")
        #expect(MarkdownPreviewLayout.editorAndPreview.symbolName == "rectangle.split.2x1")
        #expect(MarkdownPreviewLayout.previewOnly.symbolName == "eye")
    }

    @Test
    func iconsComeFromTheCatalogOrFallBackToSymbols() {
        for layout in MarkdownPreviewLayout.allCases {
            for orientation in [true, false] {
                let name = layout.iconName(isVerticalSplit: orientation)
                var queried: [String] = []
                _ = layout.icon(isVerticalSplit: orientation, hasCatalogIcon: { queried.append($0); return true })
                _ = layout.icon(isVerticalSplit: orientation, hasCatalogIcon: { queried.append($0); return false })
                _ = layout.icon(isVerticalSplit: orientation)
                #expect(queried == [name, name])
            }
        }
    }

    @Test
    func theWorkspaceStoresTheLayoutsAndTheSplitWeightsOfItsStore() throws {
        try withTempDir { directory in
            let settings = Dreamder.Settings(baseURL: directory)
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let store = MarkdownPreviewLayoutStore.store(for: workspace, settings: settings)
            #expect(MarkdownPreviewLayoutStore.store(for: workspace, settings: settings) === store)
            #expect(workspace.markdownPreviewState(for: .markdownPreviewLayouts) == nil)
            #expect(workspace.markdownPreviewState(for: .markdownPreviewSplitWeights) == nil)

            store.select(.previewOnly, for: file)
            store.splitWeights = [0.25, 0.75]

            let key = MarkdownPreviewLayoutStore.key(for: file)
            let layouts = workspace.markdownPreviewState(for: .markdownPreviewLayouts) as? [String: String]
            #expect(layouts == [key: "previewOnly"])
            #expect(workspace.markdownPreviewState(for: .markdownPreviewSplitWeights) as? [Double] == [0.25, 0.75])

            let restored = MarkdownPreviewLayoutStore(storage: workspace, settings: settings)
            #expect(restored.layout(for: file) == .previewOnly)
            #expect(restored.splitWeights == [0.25, 0.75])

            workspace.storeMarkdownPreviewState(nil, for: .markdownPreviewSplitWeights)
            #expect(workspace.markdownPreviewState(for: .markdownPreviewSplitWeights) == nil)
        }
    }

    @Test
    func theEditorWithPreviewBindingRejectsWeightsOfTheWrongCount() throws {
        try withTempDir { directory in
            let store = MarkdownPreviewLayoutStore(storage: nil, settings: Dreamder.Settings(baseURL: directory))
            let binding = MarkdownEditorWithPreview.weights(of: store)
            #expect(binding.wrappedValue == [0.5, 0.5])

            binding.wrappedValue = [0.3, 0.3, 0.4]
            #expect(store.splitWeights == [0.5, 0.5])

            binding.wrappedValue = [0.3, 0.7]
            #expect(store.splitWeights == [0.3, 0.7])
            #expect(binding.wrappedValue == [0.3, 0.7])
        }
    }
}
