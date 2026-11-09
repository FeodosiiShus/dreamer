import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation

final class FoldingCoordinator: TextViewCoordinator {
    typealias RegionLoader = @MainActor (_ text: String, _ tabWidth: Int) async -> [FoldRegion]

    private struct Context {
        let textView: TextView
        let snapshot: FoldSnapshot
        let attachments: [AnyTextAttachment]
        let selections: [NSRange]
        let style: FoldPlaceholderStyle

        var caretLine: Int {
            snapshot.index.line(containing: selections.first?.location ?? 0)
        }
    }

    private(set) var regions: [FoldRegion] = []

    private weak var controller: TextViewController?
    private let regionLoader: RegionLoader
    private let debounce: Duration
    private var refreshTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var textGeneration = 0
    private var loadedGeneration: Int?

    init(
        editorInstance: EditorInstance,
        codeFile: CodeFileDocument,
        clientProvider: (@MainActor () -> LanguageServer<CodeFileDocument>?)? = nil,
        debounce: Duration = .milliseconds(400),
        regionLoader: RegionLoader? = nil
    ) {
        let fileURL = codeFile.fileURL
        let provider: @MainActor () -> LanguageServer<CodeFileDocument>?
        if let clientProvider {
            provider = clientProvider
        } else {
            provider = {
                fileURL.flatMap { LSPService.shared.languageClient(forDocument: $0) }
            }
        }
        self.debounce = debounce
        if let regionLoader {
            self.regionLoader = regionLoader
        } else {
            self.regionLoader = { text, tabWidth in
                await FoldRegionLoader.load(text: text, tabWidth: tabWidth, client: provider(), uri: fileURL?.lspURI)
            }
        }
        EditorFeatureHubs.hub(for: editorInstance).folding = self
    }

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
    }

    func textViewDidChangeText(controller: TextViewController) {
        textGeneration += 1
        scheduleRefresh()
    }

    func destroy() {
        refreshTask?.cancel()
        refreshTask = nil
        loadTask?.cancel()
        loadTask = nil
        controller = nil
    }

    func isCollapsed(_ region: FoldRegion) -> Bool {
        makeContext()?.snapshot.isCollapsed(region) ?? false
    }

    var collapsedRegions: [FoldRegion] {
        guard let snapshot = makeContext()?.snapshot else { return [] }
        return regions.filter { snapshot.isCollapsed($0) }
    }

    func collapseCodeBlock() async {
        await ensureRegions()
        guard let context = makeContext() else { return }
        let target = FoldCommandPlanner.regionToCollapse(
            regions: regions,
            caretLine: context.caretLine,
            isCollapsed: { context.snapshot.isCollapsed($0) }
        )
        if let target {
            collapse([target], in: context)
        }
    }

    func expandCodeBlock() {
        guard let context = makeContext() else { return }
        let folds = context.snapshot.collapsedFolds
        let target = FoldCommandPlanner.regionToExpand(
            regions: folds.map(\.region),
            caretLine: context.caretLine,
            isCollapsed: { _ in true }
        )
        if let target {
            expand(folds.filter { $0.region == target }.map(\.range), in: context)
        }
    }

    func collapseAll() async {
        await ensureRegions()
        guard let context = makeContext() else { return }
        let scope = FoldCommandPlanner.regionsForSelection(
            regions: regions,
            selection: context.selections.first,
            index: context.snapshot.index
        )
        collapse(
            FoldCommandPlanner.regionsToCollapse(scope: scope, isCollapsed: { context.snapshot.isCollapsed($0) }),
            in: context
        )
    }

    func expandAll() {
        guard let context = makeContext() else { return }
        let folds = context.snapshot.collapsedFolds
        let scope = FoldCommandPlanner.regionsForSelection(
            regions: folds.map(\.region),
            selection: context.selections.first,
            index: context.snapshot.index
        )
        expand(folds.filter { scope.contains($0.region) }.map(\.range), in: context)
    }

    func collapseComments() async {
        await ensureRegions()
        guard let context = makeContext() else { return }
        collapse(
            FoldCommandPlanner.commentRegions(in: regions, isCollapsed: { context.snapshot.isCollapsed($0) }),
            in: context
        )
    }

    func ensureRegions() async {
        while loadedGeneration != textGeneration {
            if loadTask == nil {
                loadTask = Task { @MainActor [weak self] in
                    await self?.loadOnce()
                }
            }
            _ = await loadTask?.value
        }
    }

    private func loadOnce() async {
        let generation = textGeneration
        let text = controller?.textView?.textStorage.string ?? ""
        let tabWidth = controller?.tabWidth ?? 4
        let loaded = await regionLoader(text, tabWidth)
        if generation == textGeneration {
            regions = loaded
            loadedGeneration = generation
        }
        loadTask = nil
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        guard loadedGeneration != nil else {
            refreshTask = nil
            return
        }
        let delay = debounce
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.ensureRegions()
        }
    }

    private func makeContext() -> Context? {
        guard let controller, let textView = controller.textView else { return nil }
        let everything = NSRange(location: 0, length: textView.textStorage.length + 1)
        let attachments = textView.layoutManager.attachments
            .getAttachmentsOverlapping(everything)
            .filter { $0.range.length > 0 }
        let snapshot = FoldSnapshot(
            index: FoldLineIndex(text: textView.textStorage.string),
            attachmentRanges: attachments.map(\.range)
        )
        return Context(
            textView: textView,
            snapshot: snapshot,
            attachments: attachments,
            selections: textView.selectionManager.textSelections.map(\.range),
            style: FoldPlaceholderStyle.make(font: controller.font, invisibles: controller.theme.invisibles.color)
        )
    }

    private func collapse(_ targets: [FoldRegion], in context: Context) {
        let manager = context.textView.layoutManager.attachments
        var hiddenRanges: [NSRange] = []
        for region in targets {
            guard let hidden = context.snapshot.index.hiddenRange(of: region) else { continue }
            manager.add(FoldPlaceholderAttachment(region: region, style: context.style), for: hidden)
            hiddenRanges.append(hidden)
        }
        if let relocated = FoldCaretRelocator.relocated(context.selections, hiding: hiddenRanges) {
            context.textView.selectionManager.setSelectedRanges(relocated)
        }
        context.textView.needsLayout = true
    }

    private func expand(_ ranges: [NSRange], in context: Context) {
        let manager = context.textView.layoutManager.attachments
        for target in context.attachments where ranges.contains(target.range) {
            detach(target, from: manager)
        }
        context.textView.needsLayout = true
    }

    private func detach(_ target: AnyTextAttachment, from manager: TextAttachmentManager) {
        var displaced: [AnyTextAttachment] = []
        while let removed = manager.remove(atOffset: target.range.location) {
            if removed.attachment === target.attachment {
                break
            }
            displaced.append(removed)
        }
        for other in displaced {
            manager.add(other.attachment, for: other.range)
        }
    }
}
