import Foundation
import SwiftUI
import Testing
@testable import Dreamder

extension MarkdownPreviewLayoutStoreTests {
    @Test
    func clickingTheSelectedEditorAndPreviewToggleFlipsTheOrientation() throws {
        try withTempDir { directory in
            let harness = MarkdownPreviewStoreHarness(directory: directory)
            let store = harness.makeStore()
            #expect(store.layout(for: first) == .editorAndPreview)
            #expect(store.splitAxis(for: first) == .horizontal)

            store.select(.editorAndPreview, for: first)
            #expect(store.splitAxis(for: first) == .vertical)
            #expect(store.splitAxis(for: second) == .horizontal)
            #expect(store.isVerticalSplit)

            store.select(.editorAndPreview, for: first)
            #expect(store.splitAxis(for: first) == .horizontal)
            #expect(harness.storage.writes.isEmpty)
        }
    }

    @Test
    func clickingOtherSelectedTogglesDoesNothing() throws {
        try withTempDir { directory in
            let harness = MarkdownPreviewStoreHarness(directory: directory)
            let store = harness.makeStore()
            store.select(.editorOnly, for: first)
            let writes = harness.storage.writes
            store.select(.editorOnly, for: first)
            #expect(store.splitAxis(for: first) == .horizontal)
            #expect(harness.storage.writes == writes)
            store.select(.previewOnly, for: first)
            store.select(.previewOnly, for: first)
            #expect(store.splitAxis(for: first) == .horizontal)
        }
    }

    @Test
    func manuallyFlippedOrientationSurvivesLayoutChanges() throws {
        try withTempDir { directory in
            let store = MarkdownPreviewStoreHarness(directory: directory).makeStore()
            store.select(.editorAndPreview, for: first)
            store.select(.previewOnly, for: first)
            store.select(.editorAndPreview, for: first)
            #expect(store.splitAxis(for: first) == .vertical)
        }
    }

    @Test
    func changingTheGlobalSettingClearsManualFlips() throws {
        try withTempDir { directory in
            let store = MarkdownPreviewStoreHarness(directory: directory).makeStore()
            store.select(.editorAndPreview, for: first)
            #expect(store.splitAxis(for: first) == .vertical)
            store.setVerticalSplit(true)
            #expect(store.splitAxis(for: first) == .horizontal)
        }
    }

    @Test
    func emptyDocumentForcesEditorOnlyWithoutPersistingIt() throws {
        try withTempDir { directory in
            let harness = MarkdownPreviewStoreHarness(directory: directory)
            let store = harness.makeStore()
            store.select(.previewOnly, for: first)
            let writes = harness.storage.writes

            store.didOpen(first, isDocumentEmpty: true)
            #expect(store.layout(for: first) == .editorOnly)
            #expect(store.layout(for: second) == .previewOnly)
            #expect(harness.storage.writes == writes)
            #expect(harness.settings.preferences.markdownPreview.lastLayout == .previewOnly)
            #expect(store.fileLayouts[MarkdownPreviewLayoutStore.key(for: first)] == .previewOnly)
        }
    }

    @Test
    func emptyDocumentUsesEditorOnlyEvenWhenTheDefaultIsEditorAndPreview() throws {
        try withTempDir { directory in
            let store = MarkdownPreviewStoreHarness(directory: directory).makeStore()
            store.didOpen(first, isDocumentEmpty: true)
            #expect(store.layout(for: first) == .editorOnly)
            #expect(store.lastUsedLayout == .editorAndPreview)
        }
    }

    @Test
    func choosingALayoutLiftsTheEmptyDocumentOverride() throws {
        try withTempDir { directory in
            let store = MarkdownPreviewStoreHarness(directory: directory).makeStore()
            store.didOpen(first, isDocumentEmpty: true)
            store.select(.editorAndPreview, for: first)
            #expect(store.layout(for: first) == .editorAndPreview)
            #expect(store.forcedLayouts.isEmpty)
        }
    }

    @Test
    func reopeningANonEmptyDocumentRestoresTheNormalLayout() throws {
        try withTempDir { directory in
            let store = MarkdownPreviewStoreHarness(directory: directory).makeStore()
            store.didOpen(first, isDocumentEmpty: true)
            store.didOpen(first, isDocumentEmpty: false)
            #expect(store.layout(for: first) == .editorAndPreview)
        }
    }

    @Test
    func splitWeightsDefaultToAnEvenSplit() throws {
        try withTempDir { directory in
            let store = MarkdownPreviewStoreHarness(directory: directory).makeStore()
            #expect(store.splitWeights == [0.5, 0.5])
            #expect(MarkdownPreviewLayoutStore.defaultSplitWeights == [0.5, 0.5])
        }
    }

    @Test
    func splitWeightsArePersistedInTheWorkspaceState() throws {
        try withTempDir { directory in
            let harness = MarkdownPreviewStoreHarness(directory: directory)
            let store = harness.makeStore()
            store.splitWeights = [0.25, 0.75]
            #expect(harness.storage.values[.markdownPreviewSplitWeights] as? [Double] == [0.25, 0.75])
            #expect(harness.makeStore().splitWeights == [0.25, 0.75])
        }
    }

    @Test
    func unchangedSplitWeightsAreNotWrittenAgain() throws {
        try withTempDir { directory in
            let harness = MarkdownPreviewStoreHarness(directory: directory)
            let store = harness.makeStore()
            store.splitWeights = [0.3, 0.7]
            store.splitWeights = [0.3, 0.7]
            #expect(harness.storage.writes.filter { $0 == .markdownPreviewSplitWeights }.count == 1)
        }
    }

    @Test
    func storedSplitWeightsAreNormalizedAndInvalidOnesFallBack() throws {
        try withTempDir { directory in
            let harness = MarkdownPreviewStoreHarness(directory: directory)
            harness.storage.seed([1.0, 3.0], for: .markdownPreviewSplitWeights)
            #expect(harness.makeStore().splitWeights == [0.25, 0.75])
            for invalid in [[1.0], [1.0, 2.0, 3.0], [0.0, 1.0], [-1.0, 2.0], [Double.nan, 1.0]] {
                harness.storage.seed(invalid, for: .markdownPreviewSplitWeights)
                #expect(harness.makeStore().splitWeights == [0.5, 0.5])
            }
            harness.storage.seed("garbage", for: .markdownPreviewSplitWeights)
            #expect(harness.makeStore().splitWeights == [0.5, 0.5])
        }
    }

    @Test
    func layoutIconsFollowTheOrientationAndExistInTheCatalog() {
        #expect(MarkdownPreviewLayout.editorOnly.iconName(isVerticalSplit: true) == "general/editorOnly")
        #expect(MarkdownPreviewLayout.previewOnly.iconName(isVerticalSplit: false) == "general/previewOnly")
        #expect(MarkdownPreviewLayout.editorAndPreview.iconName(isVerticalSplit: true) == "general/editorPreview")
        #expect(
            MarkdownPreviewLayout.editorAndPreview.iconName(isVerticalSplit: false) == "general/editorPreviewVertical"
        )
        for layout in MarkdownPreviewLayout.allCases {
            for orientation in [true, false] {
                #expect(IntelliJIcon.nsImage(layout.iconName(isVerticalSplit: orientation)) != nil)
            }
        }
    }

    @Test
    func layoutTitlesAndRawValuesAreStable() {
        #expect(MarkdownPreviewLayout.allCases.map(\.rawValue) == ["editorOnly", "editorAndPreview", "previewOnly"])
        #expect(MarkdownPreviewLayout.allCases.map(\.title) == ["Editor Only", "Editor and Preview", "Preview Only"])
        #expect(MarkdownPreviewLayout.allCases.map(\.id) == MarkdownPreviewLayout.allCases.map(\.rawValue))
    }

    @Test
    func workspaceStoresAreSharedPerWorkspace() {
        let workspace = WorkspaceDocument()
        let other = WorkspaceDocument()
        #expect(MarkdownPreviewLayoutStore.store(for: workspace) === MarkdownPreviewLayoutStore.store(for: workspace))
        #expect(MarkdownPreviewLayoutStore.store(for: workspace) !== MarkdownPreviewLayoutStore.store(for: other))
    }

    @Test
    func aCachedStoreDoesNotKeepItsWorkspaceAlive() throws {
        try withTempDir { directory in
            let settings = Dreamder.Settings(baseURL: directory)
            weak var releasedWorkspace: WorkspaceDocument?
            let store: MarkdownPreviewLayoutStore = autoreleasepool {
                let workspace = WorkspaceDocument()
                releasedWorkspace = workspace
                let store = MarkdownPreviewLayoutStore.store(for: workspace, settings: settings)
                store.select(.previewOnly, for: first)
                return store
            }

            #expect(releasedWorkspace == nil)
            store.select(.editorOnly, for: second)
            store.splitWeights = [0.4, 0.6]
            #expect(store.layout(for: second) == .editorOnly)
            #expect(store.layout(for: first) == .previewOnly)
            #expect(store.splitWeights == [0.4, 0.6])
        }
    }
}
