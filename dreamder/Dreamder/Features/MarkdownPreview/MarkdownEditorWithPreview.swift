import SwiftUI

struct MarkdownEditorWithPreview: View {
    static let minimumPaneLength: CGFloat = 120

    private let editorInstance: EditorInstance
    private let codeFile: CodeFileDocument

    @Environment(WorkspaceDocument.self) private var workspace

    @State private var model: MarkdownPreviewModel
    @State private var scrollSync = MarkdownScrollSyncCoordinator()

    init(editorInstance: EditorInstance, codeFile: CodeFileDocument) {
        self.editorInstance = editorInstance
        self.codeFile = codeFile
        self._model = State(wrappedValue: MarkdownPreviewModel(codeFile: codeFile))
    }

    var body: some View {
        let store = MarkdownPreviewLayoutStore.store(for: workspace)
        let url = codeFile.fileURL
        let layout = store.layout(for: url)
        SplitView(
            axis: store.splitAxis(for: url),
            dividerStyle: .editorDivider,
            weights: Self.weights(of: store)
        ) {
            if layout != .previewOnly {
                CodeFileView(
                    editorInstance: editorInstance,
                    codeFile: codeFile,
                    textViewCoordinators: [scrollSync]
                )
                .clipped()
                .splitPaneMinLength(Self.minimumPaneLength)
            }
            if layout != .editorOnly {
                MarkdownPreviewPane(model: model, scrollState: scrollSync.scrollState, store: store)
                    .splitPaneMinLength(Self.minimumPaneLength)
            }
        }
        .task {
            model.start()
        }
        .onAppear {
            store.didOpen(url, isDocumentEmpty: codeFile.content?.length == 0)
        }
        .onChange(of: layout != .editorOnly) { _, showsPreview in
            if showsPreview {
                model.refresh()
            }
        }
    }

    static func weights(of store: MarkdownPreviewLayoutStore) -> Binding<[CGFloat]> {
        Binding(
            get: { store.splitWeights },
            set: { newValue in
                if newValue.count == store.splitWeights.count {
                    store.splitWeights = newValue
                }
            }
        )
    }
}

private struct MarkdownPreviewPane: View {
    let model: MarkdownPreviewModel
    let scrollState: MarkdownPreviewScrollState
    let store: MarkdownPreviewLayoutStore

    var body: some View {
        MarkdownPreviewWebView(
            bodyHTML: model.bodyHTML,
            baseURL: model.baseURL,
            palette: MarkdownPreviewPalette.current(),
            followOffset: store.isAutoScrollEnabled ? scrollState.sourceOffset : nil
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
