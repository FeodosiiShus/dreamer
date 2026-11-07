import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
final class FakeMarkdownPreviewStorage: MarkdownPreviewStateStorage {
    private(set) var values: [WorkspaceStateKey: Any] = [:]
    private(set) var writes: [WorkspaceStateKey] = []

    func markdownPreviewState(for key: WorkspaceStateKey) -> Any? {
        values[key]
    }

    func storeMarkdownPreviewState(_ value: Any?, for key: WorkspaceStateKey) {
        writes.append(key)
        values[key] = value
    }

    func seed(_ value: Any?, for key: WorkspaceStateKey) {
        values[key] = value
    }
}

@MainActor
struct MarkdownPreviewStoreHarness {
    let settings: Dreamder.Settings
    let storage = FakeMarkdownPreviewStorage()

    init(directory: URL) {
        settings = Dreamder.Settings(baseURL: directory)
    }

    func makeStore() -> MarkdownPreviewLayoutStore {
        MarkdownPreviewLayoutStore(storage: storage, settings: settings)
    }
}

@MainActor
@Suite
struct MarkdownPreviewLayoutStoreTests {
    private let first = URL(fileURLWithPath: "/tmp/project/a.md")
    private let second = URL(fileURLWithPath: "/tmp/project/b.md")

    @Test
    func markdownExtensionsAreRecognized() {
        #expect(MarkdownPreviewLayoutStore.isMarkdownFile(URL(fileURLWithPath: "/tmp/README.md")))
        #expect(MarkdownPreviewLayoutStore.isMarkdownFile(URL(fileURLWithPath: "/tmp/notes.markdown")))
        #expect(MarkdownPreviewLayoutStore.isMarkdownFile(URL(fileURLWithPath: "/tmp/README.MD")))
        #expect(!MarkdownPreviewLayoutStore.isMarkdownFile(URL(fileURLWithPath: "/tmp/main.swift")))
        #expect(!MarkdownPreviewLayoutStore.isMarkdownFile(nil))
    }

    @Test
    func keysAreStandardizedPaths() {
        #expect(MarkdownPreviewLayoutStore.key(for: URL(fileURLWithPath: "/Users/test/a/../b.md")) == "/Users/test/b.md")
    }

    @Test
    func defaultLayoutIsEditorAndPreviewWithSideBySideOrientation() throws {
        try withTempDir { directory in
            let store = MarkdownPreviewStoreHarness(directory: directory).makeStore()
            #expect(MarkdownPreviewLayoutStore.defaultLayout == .editorAndPreview)
            #expect(store.layout(for: first) == .editorAndPreview)
            #expect(store.layout(for: nil) == .editorAndPreview)
            #expect(store.isVerticalSplit)
            #expect(store.splitAxis(for: first) == .horizontal)
            #expect(store.isAutoScrollEnabled)
        }
    }

    @Test
    func selectingALayoutStoresItPerFileAndAsTheLastUsedGlobalLayout() throws {
        try withTempDir { directory in
            let harness = MarkdownPreviewStoreHarness(directory: directory)
            let store = harness.makeStore()
            store.select(.previewOnly, for: first)

            #expect(store.layout(for: first) == .previewOnly)
            #expect(store.fileLayouts[MarkdownPreviewLayoutStore.key(for: first)] == .previewOnly)
            #expect(harness.settings.preferences.markdownPreview.lastLayout == .previewOnly)
            let stored = harness.storage.values[.markdownPreviewLayouts] as? [String: String]
            #expect(stored == ["/tmp/project/a.md": "previewOnly"])
        }
    }

    @Test
    func newFilesOpenWithTheLastUsedLayoutWhileExistingOverridesStay() throws {
        try withTempDir { directory in
            let store = MarkdownPreviewStoreHarness(directory: directory).makeStore()
            store.select(.editorOnly, for: first)
            store.select(.previewOnly, for: second)

            #expect(store.layout(for: first) == .editorOnly)
            #expect(store.layout(for: second) == .previewOnly)
            #expect(store.layout(for: URL(fileURLWithPath: "/tmp/project/c.md")) == .previewOnly)
        }
    }

    @Test
    func perFileLayoutsSurviveARestartThroughTheWorkspaceState() throws {
        try withTempDir { directory in
            let harness = MarkdownPreviewStoreHarness(directory: directory)
            harness.makeStore().select(.previewOnly, for: first)

            let restored = harness.makeStore()
            #expect(restored.layout(for: first) == .previewOnly)
            #expect(restored.layout(for: second) == restored.lastUsedLayout)
        }
    }

    @Test
    func unknownStoredLayoutsAreIgnored() throws {
        try withTempDir { directory in
            let harness = MarkdownPreviewStoreHarness(directory: directory)
            harness.storage.seed(
                ["/tmp/project/a.md": "sideways", "/tmp/project/b.md": "editorOnly"],
                for: .markdownPreviewLayouts
            )
            let store = harness.makeStore()
            #expect(store.layout(for: first) == .editorAndPreview)
            #expect(store.layout(for: second) == .editorOnly)
        }
    }

    @Test
    func missingURLIsNeverStored() throws {
        try withTempDir { directory in
            let harness = MarkdownPreviewStoreHarness(directory: directory)
            let store = harness.makeStore()
            store.setLayout(.previewOnly, for: nil)
            store.select(.previewOnly, for: nil)
            store.toggleOrientation(for: nil)
            store.didOpen(nil, isDocumentEmpty: true)
            #expect(store.layout(for: nil) == .editorAndPreview)
            #expect(store.fileLayouts.isEmpty)
            #expect(harness.storage.writes.isEmpty)
        }
    }

    @Test
    func globalOrientationAppliesToEveryFile() throws {
        try withTempDir { directory in
            let store = MarkdownPreviewStoreHarness(directory: directory).makeStore()
            store.setVerticalSplit(false)
            #expect(!store.isVerticalSplit(for: first))
            #expect(store.splitAxis(for: first) == .vertical)
            #expect(store.splitAxis(for: second) == .vertical)
        }
    }

    @Test
    func globalOrientationWinsOverARestoredPerFileOrientation() throws {
        try withTempDir { directory in
            let harness = MarkdownPreviewStoreHarness(directory: directory)
            harness.settings.preferences.markdownPreview.isVerticalSplit = false

            let flipped = harness.makeStore()
            flipped.select(.editorAndPreview, for: first)
            #expect(flipped.splitAxis(for: first) == .horizontal)

            let restored = harness.makeStore()
            #expect(restored.layout(for: first) == .editorAndPreview)
            #expect(restored.splitAxis(for: first) == .vertical)
        }
    }

    @Test
    func orientationAppliesToAFreshlyCreatedStore() throws {
        try withTempDir { directory in
            let harness = MarkdownPreviewStoreHarness(directory: directory)
            harness.settings.preferences.markdownPreview.isVerticalSplit = false
            #expect(harness.makeStore().splitAxis(for: first) == .vertical)
        }
    }

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
}
