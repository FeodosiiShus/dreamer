import AppKit
import CodeEditTextView
import Foundation

@MainActor
final class EditorFeatureHub {
    weak var signatureHelp: SignatureHelpCoordinator?
    weak var selectionRange: SelectionRangeCoordinator?
    weak var folding: FoldingCoordinator?
}

@MainActor
enum EditorFeatureHubs {
    private static let hubs = NSMapTable<EditorInstance, EditorFeatureHub>(
        keyOptions: [.weakMemory, .objectPointerPersonality],
        valueOptions: .strongMemory
    )

    static func hub(for tab: EditorInstance) -> EditorFeatureHub {
        if let existing = hubs.object(forKey: tab) {
            return existing
        }
        let hub = EditorFeatureHub()
        hubs.setObject(hub, forKey: tab)
        return hub
    }

    static func activeHub(in workspace: WorkspaceDocument?) -> EditorFeatureHub? {
        guard let tab = workspace?.editorManager?.activeEditor.selectedTab else { return nil }
        return hub(for: tab)
    }
}

@MainActor
enum EditorCaretGeometry {
    static func screenRect(ofOffset offset: Int, in textView: TextView) -> NSRect? {
        guard let window = textView.window,
              let caret = textView.layoutManager.rectForOffset(offset) else {
            return nil
        }
        return window.convertToScreen(textView.convert(caret, to: nil))
    }
}

@MainActor
enum EditorFeatureCommands {
    static func expandSelection(workspace: WorkspaceDocument?) async {
        await EditorFeatureHubs.activeHub(in: workspace)?.selectionRange?.expandSelection()
    }

    static func shrinkSelection(workspace: WorkspaceDocument?) {
        EditorFeatureHubs.activeHub(in: workspace)?.selectionRange?.shrinkSelection()
    }

    static func showParameterInfo(workspace: WorkspaceDocument?) async {
        await EditorFeatureHubs.activeHub(in: workspace)?.signatureHelp?.showParameterInfo()
    }

    static func collapseCodeBlock(workspace: WorkspaceDocument?) async {
        await EditorFeatureHubs.activeHub(in: workspace)?.folding?.collapseCodeBlock()
    }

    static func expandCodeBlock(workspace: WorkspaceDocument?) {
        EditorFeatureHubs.activeHub(in: workspace)?.folding?.expandCodeBlock()
    }

    static func collapseAll(workspace: WorkspaceDocument?) async {
        await EditorFeatureHubs.activeHub(in: workspace)?.folding?.collapseAll()
    }

    static func expandAll(workspace: WorkspaceDocument?) {
        EditorFeatureHubs.activeHub(in: workspace)?.folding?.expandAll()
    }

    static func collapseComments(workspace: WorkspaceDocument?) async {
        await EditorFeatureHubs.activeHub(in: workspace)?.folding?.collapseComments()
    }
}
