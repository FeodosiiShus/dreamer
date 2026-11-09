import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import LanguageServerProtocol

final class SelectionRangeCoordinator: TextViewCoordinator {
    typealias Client = LanguageServer<CodeFileDocument>
    typealias ClientProvider = @MainActor () -> Client?

    let clientProvider: ClientProvider

    private weak var controller: TextViewController?
    private weak var codeFile: CodeFileDocument?
    private var stacks: [CaretSelectionStack] = []
    private var appliedRanges: [NSRange] = []
    private var epoch = 0
    private var expansionTail: Task<Void, Never>?

    init(
        editorInstance: EditorInstance,
        codeFile: CodeFileDocument,
        clientProvider: (@MainActor () -> LanguageServer<CodeFileDocument>?)? = nil
    ) {
        self.codeFile = codeFile
        if let clientProvider {
            self.clientProvider = clientProvider
        } else {
            self.clientProvider = { [weak codeFile] in
                guard let fileURL = codeFile?.fileURL else { return nil }
                return LSPService.shared.languageClient(forDocument: fileURL)
            }
        }
        EditorFeatureHubs.hub(for: editorInstance).selectionRange = self
    }

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
    }

    func textViewDidChangeText(controller: TextViewController) {
        reset()
    }

    func textViewDidChangeSelection(controller: TextViewController, newPositions: [CursorPosition]) {
        guard !stacks.isEmpty, let textView = controller.textView else { return }
        if liveRanges(in: textView) != appliedRanges {
            reset()
        }
    }

    func destroy() {
        expansionTail?.cancel()
        expansionTail = nil
        reset()
        controller = nil
    }

    func expandSelection() async {
        let previous = expansionTail
        let task = Task { @MainActor [weak self] in
            await previous?.value
            await self?.expandNow()
        }
        expansionTail = task
        await task.value
    }

    func shrinkSelection() {
        guard let textView = controller?.textView else { return }
        prepareStacks(in: textView)
        apply(in: textView) { stack, text in stack.shrink(in: text) }
    }

    private func expandNow() async {
        guard let textView = controller?.textView else { return }
        prepareStacks(in: textView)
        let pending = stacks.indices.filter { stacks[$0].serverChain == nil }
        if !pending.isEmpty {
            let token = epoch
            let offsets = pending.map { stacks[$0].requestOffset }
            let chains = await serverChains(at: offsets, in: textView)
            prepareStacks(in: textView)
            guard token == epoch else { return }
            for (index, chain) in zip(pending, chains) {
                stacks[index].serverChain = chain
            }
        }
        apply(in: textView) { stack, text in stack.expand(in: text) }
    }

    private func serverChains(at offsets: [Int], in textView: TextView) async -> [[NSRange]] {
        let none = offsets.map { _ in [NSRange]() }
        guard let client = clientProvider(),
              client.supportsSelectionRange,
              let uri = codeFile?.languageServerURI else {
            return none
        }
        let positions = offsets.compactMap {
            textView.lspRangeFrom(nsRange: NSRange(location: $0, length: 0))?.start
        }
        guard positions.count == offsets.count,
              let response = try? await client.requestSelectionRange(for: uri, positions: positions),
              response.count == offsets.count else {
            return none
        }
        return response.map { root in
            SelectionRangeChain.ranges(from: root) { LSPTextPositionConverter.nsRange(from: $0, in: textView) }
        }
    }

    private func apply(in textView: TextView, _ transform: (inout CaretSelectionStack, NSString) -> Bool) {
        let text = textView.textStorage.string as NSString
        var changed = false
        for index in stacks.indices {
            if transform(&stacks[index], text) {
                changed = true
            }
        }
        guard changed else { return }
        var unique: [CaretSelectionStack] = []
        let ordered = stacks.sorted { ($0.current.location, $0.requestOffset) < ($1.current.location, $1.requestOffset) }
        for stack in ordered
        where !unique.contains(where: { $0.current == stack.current }) {
            unique.append(stack)
        }
        stacks = unique
        epoch += 1
        let ranges = unique.map(\.current)
        appliedRanges = Self.normalized(ranges)
        textView.selectionManager.setSelectedRanges(ranges)
        appliedRanges = liveRanges(in: textView)
        textView.scrollSelectionToVisible()
    }

    private func prepareStacks(in textView: TextView) {
        let live = liveRanges(in: textView)
        guard stacks.isEmpty || live != appliedRanges else { return }
        stacks = live.map { CaretSelectionStack(selection: $0) }
        appliedRanges = live
        epoch += 1
    }

    private func liveRanges(in textView: TextView) -> [NSRange] {
        Self.normalized(textView.selectionManager.textSelections.map(\.range))
    }

    private static func normalized(_ ranges: [NSRange]) -> [NSRange] {
        ranges.sorted { ($0.location, $0.length) < ($1.location, $1.length) }
    }

    private func reset() {
        stacks = []
        appliedRanges = []
        epoch += 1
    }
}
