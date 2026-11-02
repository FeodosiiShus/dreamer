import Foundation
import Testing
@testable import Dreamder

@Suite
struct MarkdownPreviewLayoutStoreTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let name = "MarkdownPreviewLayoutStoreTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name) ?? .standard, name)
    }

    @Test
    func markdownExtensionsAreRecognized() {
        #expect(MarkdownPreviewLayoutStore.isMarkdownFile(URL(fileURLWithPath: "/tmp/README.md")))
        #expect(MarkdownPreviewLayoutStore.isMarkdownFile(URL(fileURLWithPath: "/tmp/notes.markdown")))
        #expect(MarkdownPreviewLayoutStore.isMarkdownFile(URL(fileURLWithPath: "/tmp/README.MD")))
        #expect(!MarkdownPreviewLayoutStore.isMarkdownFile(URL(fileURLWithPath: "/tmp/main.swift")))
        #expect(!MarkdownPreviewLayoutStore.isMarkdownFile(nil))
    }

    @Test
    func defaultLayoutIsEditorAndPreview() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = MarkdownPreviewLayoutStore(defaults: defaults)
        #expect(store.layout(for: URL(fileURLWithPath: "/tmp/a.md")) == .editorAndPreview)
        #expect(MarkdownPreviewLayoutStore.defaultLayout == .editorAndPreview)
    }

    @Test
    func layoutIsPersistedPerFile() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let first = MarkdownPreviewLayoutStore(defaults: defaults)
        let otherFile = URL(fileURLWithPath: "/tmp/b.md")
        first.setLayout(.previewOnly, for: URL(fileURLWithPath: "/tmp/a.md"))

        let second = MarkdownPreviewLayoutStore(defaults: defaults)
        #expect(second.layout(for: URL(fileURLWithPath: "/tmp/a.md")) == .previewOnly)
        #expect(second.layout(for: otherFile) == .editorAndPreview)
    }

    @Test
    func layoutIsStoredUnderStableKey() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = MarkdownPreviewLayoutStore(defaults: defaults)
        let url = URL(fileURLWithPath: "/tmp/a.md")
        store.setLayout(.editorOnly, for: url)
        #expect(defaults.string(forKey: "markdownPreviewLayout./tmp/a.md") == "editorOnly")
        #expect(store.layout(for: url) == .editorOnly)
    }

    @Test
    func unknownStoredValueFallsBackToDefault() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let url = URL(fileURLWithPath: "/tmp/a.md")
        defaults.set("sideways", forKey: MarkdownPreviewLayoutStore.key(for: url))
        let store = MarkdownPreviewLayoutStore(defaults: defaults)
        #expect(store.layout(for: url) == .editorAndPreview)
    }

    @Test
    func layoutForMissingURLIsDefaultAndNotStored() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = MarkdownPreviewLayoutStore(defaults: defaults)
        store.setLayout(.previewOnly, for: nil)
        #expect(store.layout(for: nil) == .editorAndPreview)
        #expect(store.layouts.isEmpty)
    }
}
