import AppKit
import Combine
import SwiftUI

final class MarkdownPreviewModel: ObservableObject {
    @Published private(set) var bodyHTML: String

    let baseURL: URL?

    private let codeFile: CodeFileDocument
    private var cancellables: Set<AnyCancellable> = []
    private var renderGeneration = 0
    private let renderQueue = DispatchQueue(label: "dev.dreamer.markdownPreview.render", qos: .userInitiated)

    init(codeFile: CodeFileDocument) {
        self.codeFile = codeFile
        self.baseURL = codeFile.fileURL?.deletingLastPathComponent()
        self.bodyHTML = ""
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
        let model = self

        renderQueue.async {
            let html = MarkdownHTMLRenderer.bodyHTML(from: text)
            DispatchQueue.main.async {
                guard generation == model.renderGeneration, html != model.bodyHTML else { return }
                model.bodyHTML = html
            }
        }
    }
}

struct MarkdownEditorWithPreview: View {
    @ObservedObject private var editorInstance: EditorInstance
    @ObservedObject private var codeFile: CodeFileDocument
    @ObservedObject private var layouts = MarkdownPreviewLayoutStore.shared

    @StateObject private var model: MarkdownPreviewModel
    @State private var splitFraction: CGFloat = 0.5
    @State private var dragStartFraction: CGFloat = 0.5

    private let dividerWidth: CGFloat = 7
    private let minimumFraction: CGFloat = 0.15
    private let maximumFraction: CGFloat = 0.85

    init(editorInstance: EditorInstance, codeFile: CodeFileDocument) {
        self._editorInstance = .init(wrappedValue: editorInstance)
        self._codeFile = .init(wrappedValue: codeFile)
        self._model = .init(wrappedValue: MarkdownPreviewModel(codeFile: codeFile))
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
        .overlay(alignment: .topTrailing) {
            MarkdownPreviewLayoutButtons(layout: layout) { selected in
                layouts.setLayout(selected, for: fileURL)
            }
            .padding(.trailing, 8)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func editorPane(availableWidth: CGFloat) -> some View {
        if layout == .editorAndPreview {
            CodeFileView(editorInstance: editorInstance, codeFile: codeFile)
                .frame(
                    width: max(0, (availableWidth - dividerWidth) * splitFraction),
                    height: nil,
                    alignment: .topLeading
                )
                .clipped()
        } else {
            CodeFileView(editorInstance: editorInstance, codeFile: codeFile)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
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
