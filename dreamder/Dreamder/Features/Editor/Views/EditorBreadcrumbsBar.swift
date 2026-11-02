import AppKit
import CodeEditSourceEditor
import Combine
import SwiftUI

@MainActor
final class EditorBreadcrumbsModel: ObservableObject {
    @Published private(set) var crumbs: [StructureNode] = []

    private var nodes: [StructureNode] = []
    private var line = 1
    private weak var document: CodeFileDocument?
    private var url: URL?
    private var lspService: LSPService?
    private var cancellables = Set<AnyCancellable>()
    private var reloadTask: Task<Void, Never>?

    func bind(instance: EditorInstance, document: CodeFileDocument, lspService: LSPService) {
        guard document !== self.document else { return }
        cancellables.removeAll()
        reloadTask?.cancel()
        self.document = document
        self.url = instance.file.url.standardizedFileURL
        self.lspService = lspService
        nodes = []
        crumbs = []
        instance.$cursorPositions
            .sink { [weak self] positions in
                guard let self, let position = positions.first else { return }
                self.line = self.line(for: position)
                self.updateCrumbs()
            }
            .store(in: &cancellables)
        document.contentCoordinator.textUpdatePublisher
            .sink { [weak self] _ in
                Task { @MainActor in self?.scheduleReload(delay: .milliseconds(400)) }
            }
            .store(in: &cancellables)
        scheduleReload(delay: .zero)
    }

    private func line(for position: CursorPosition) -> Int {
        if position.start.line > 0 {
            return position.start.line
        }
        guard let text = document?.content?.string as NSString? else { return 1 }
        let location = min(max(position.range.location, 0), text.length)
        var line = 1
        var searchRange = NSRange(location: 0, length: location)
        while true {
            let found = text.range(of: "\n", options: .literal, range: searchRange)
            guard found.location != NSNotFound else { break }
            line += 1
            searchRange = NSRange(location: found.upperBound, length: location - found.upperBound)
        }
        return line
    }

    private func scheduleReload(delay: Duration) {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }

    private func reload() async {
        guard let document, let url else { return }
        if let client = lspService?.languageClient(forDocument: url) {
            let uri = document.languageServerURI ?? url.lspURI
            let response = try? await client.requestSymbols(for: uri)
            guard !Task.isCancelled, document === self.document else { return }
            if let response, let symbols = StructureTreeBuilder.nodes(from: response) {
                apply(symbols)
                return
            }
        }
        let text = document.content?.string ?? ""
        let extracted = SymbolExtractor.symbols(in: text, fileExtension: url.pathExtension)
        apply(StructureTreeBuilder.nodes(from: extracted, text: text))
    }

    private func apply(_ nodes: [StructureNode]) {
        self.nodes = nodes
        updateCrumbs()
    }

    private func updateCrumbs() {
        let path = StructureBreadcrumbs.path(in: nodes, line: line)
        if path != crumbs {
            crumbs = path
        }
    }
}

struct EditorBreadcrumbsBar: View {
    @Service private var lspService: LSPService

    @EnvironmentObject private var toolWindowManager: ToolWindowManager

    @StateObject private var model = EditorBreadcrumbsModel()

    let editorInstance: EditorInstance
    let codeFile: CodeFileDocument

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.crumbs.enumerated()), id: \.element.id) { index, crumb in
                if index > 0 {
                    Image("general/chevronRight")
                        .resizable()
                        .frame(width: 12, height: 12)
                }
                Text(crumb.name)
                    .foregroundStyle(
                        index == model.crumbs.count - 1 ? Islands.foreground : Islands.secondaryForeground
                    )
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .font(Islands.uiFont)
        .padding(.horizontal, 10)
        .frame(height: Islands.statusBarHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Islands.separator)
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toolWindowManager.show(.structure)
        }
        .contextMenu {
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(editorInstance.file.url.path(percentEncoded: false), forType: .string)
            }
        }
        .accessibilityIdentifier("EditorBreadcrumbs")
        .onAppear {
            model.bind(instance: editorInstance, document: codeFile, lspService: lspService)
        }
        .onChange(of: ObjectIdentifier(codeFile)) { _, _ in
            model.bind(instance: editorInstance, document: codeFile, lspService: lspService)
        }
    }
}
