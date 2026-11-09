import Foundation
import SwiftUI

extension StructureViewModel {
    @discardableResult
    func activateSelection(workspace: WorkspaceDocument) -> KeyPress.Result {
        let displayed = displayNodes
        let selected = selection.flatMap { StructureTreeTransform.find($0, in: displayed) }
        let firstMatch = isFiltering ? rows.first { !$0.node.isGroup }?.node : nil
        if let node = selected ?? firstMatch {
            activate(node, workspace: workspace)
        }
        return .handled
    }

    func submission(workspace: WorkspaceDocument, then completion: @escaping () -> Void = {}) -> () -> Void {
        {
            self.activateSelection(workspace: workspace)
            completion()
        }
    }

    func caretLine() -> Int? {
        guard let tab = workspace?.editorManager?.activeEditor.selectedTab,
              tab.file.url.standardizedFileURL == fileURL,
              let position = tab.cursorPositions.first else { return nil }
        if position.start.line > 0 {
            return position.start.line
        }
        let text = tab.file.fileDocument?.content?.string ?? ""
        return StructureCaretLine.line(offset: position.range.location, in: text)
    }

    func activeURL() -> URL? {
        workspace?.editorManager?.activeEditor.selectedTab?.file.url.standardizedFileURL
    }

    func applyFallback(document: CodeFileDocument, url: URL) async {
        let liveText = document.content?.string
        let text: String
        if let liveText {
            text = liveText
        } else {
            text = await readText(url) ?? ""
        }
        guard !Task.isCancelled, activeURL() == url else { return }
        let nodes = await buildNodes(text, url.pathExtension)
        guard !Task.isCancelled, activeURL() == url else { return }
        apply(nodes: nodes)
    }

    @concurrent
    static func fallbackNodes(text: String, fileExtension: String) async -> [StructureNode] {
        let extracted = SymbolExtractor.symbols(in: text, fileExtension: fileExtension)
        return StructureTreeBuilder.nodes(from: extracted, text: text)
    }

    func navigate(to node: StructureNode, workspace: WorkspaceDocument) {
        guard let fileURL else { return }
        EditorLocationNavigation.open(
            fileURL: fileURL,
            line: node.line,
            column: node.column,
            workspace: workspace
        )
    }
}
