import AppKit
import Combine
import Observation
import SwiftUI

@Observable
@MainActor
final class MarkdownPreviewModel {
    private(set) var bodyHTML = ""

    @ObservationIgnored let baseURL: URL?

    @ObservationIgnored private let codeFile: CodeFileDocument
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored private var renderGeneration = 0
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var isStarted = false

    init(codeFile: CodeFileDocument) {
        self.codeFile = codeFile
        self.baseURL = codeFile.fileURL?.deletingLastPathComponent()
    }

    isolated deinit {
        renderTask?.cancel()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        observeText()
        scheduleRender()
    }

    private func observeText() {
        guard let storage = codeFile.content else { return }
        NotificationCenter.default
            .publisher(for: NSTextStorage.didProcessEditingNotification, object: storage)
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleRender()
            }
            .store(in: &cancellables)
    }

    private func scheduleRender() {
        renderGeneration += 1
        let generation = renderGeneration
        let text = codeFile.content?.string ?? ""
        renderTask?.cancel()
        renderTask = Task.detached(priority: .userInitiated) { [weak self] in
            let html = MarkdownHTMLRenderer.bodyHTML(from: text)
            guard !Task.isCancelled else { return }
            await self?.apply(html, generation: generation)
        }
    }

    private func apply(_ html: String, generation: Int) {
        guard generation == renderGeneration, html != bodyHTML else { return }
        bodyHTML = html
    }
}

struct MarkdownEditorWithPreview: View {
    private let editorInstance: EditorInstance
    private let codeFile: CodeFileDocument
    private let layouts = MarkdownPreviewLayoutStore.shared

    @State private var model: MarkdownPreviewModel
    @State private var splitFraction: CGFloat = 0.5
    @State private var dragStartFraction: CGFloat = 0.5

    private let dividerWidth: CGFloat = 7
    private let minimumFraction: CGFloat = 0.15
    private let maximumFraction: CGFloat = 0.85

    init(editorInstance: EditorInstance, codeFile: CodeFileDocument) {
        self.editorInstance = editorInstance
        self.codeFile = codeFile
        self._model = State(wrappedValue: MarkdownPreviewModel(codeFile: codeFile))
    }

    private var fileURL: URL? { codeFile.fileURL }

    private var layout: MarkdownPreviewLayout { layouts.layout(for: fileURL) }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                if layout != .previewOnly {
                    editorPane(availableWidth: proxy.size.width)
                }
                if layout == .editorAndPreview {
                    divider(availableWidth: proxy.size.width)
                }
                if layout != .editorOnly {
                    MarkdownPreviewWebView(bodyHTML: model.bodyHTML, baseURL: model.baseURL)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .task {
            model.start()
        }
        .overlay(alignment: .topTrailing) {
            MarkdownPreviewLayoutButtons(layout: layout) { selected in
                layouts.setLayout(selected, for: fileURL)
            }
            .padding(.trailing, 8)
            .padding(.top, 8)
        }
    }

    private func editorPane(availableWidth: CGFloat) -> some View {
        let splitWidth: CGFloat? = layout == .editorAndPreview
            ? max(0, (availableWidth - dividerWidth) * splitFraction)
            : nil
        return CodeFileView(editorInstance: editorInstance, codeFile: codeFile)
            .frame(
                minWidth: splitWidth,
                maxWidth: splitWidth ?? .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .clipped()
    }

    private func divider(availableWidth: CGFloat) -> some View {
        Rectangle()
            .fill(Islands.separator)
            .frame(width: 1)
            .frame(width: dividerWidth)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard availableWidth > 0 else { return }
                        let moved = dragStartFraction + value.translation.width / availableWidth
                        splitFraction = min(max(moved, minimumFraction), maximumFraction)
                    }
                    .onEnded { _ in
                        dragStartFraction = splitFraction
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    splitFraction = 0.5
                    dragStartFraction = 0.5
                }
            )
    }
}

struct MarkdownPreviewLayoutButtons: View {
    let layout: MarkdownPreviewLayout
    let onSelect: (MarkdownPreviewLayout) -> Void

    @State private var hovered: MarkdownPreviewLayout?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MarkdownPreviewLayout.allCases) { mode in
                button(for: mode)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: Islands.controlRadius, style: .continuous)
                .fill(Islands.popup)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Islands.controlRadius, style: .continuous)
                .strokeBorder(Islands.popupBorder, lineWidth: 1)
        )
    }

    private func button(for mode: MarkdownPreviewLayout) -> some View {
        Button {
            onSelect(mode)
        } label: {
            mode.icon
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: Islands.rowRadius, style: .continuous)
                        .fill(background(for: mode))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(mode.title)
        .onHover { hovering in
            if hovering {
                hovered = mode
            } else if hovered == mode {
                hovered = nil
            }
        }
    }

    private func background(for mode: MarkdownPreviewLayout) -> Color {
        if mode == layout {
            return Islands.selection
        }
        if mode == hovered {
            return Islands.actionHover
        }
        return .clear
    }
}
