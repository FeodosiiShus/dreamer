import SwiftUI

extension DreamderWindowController {
    @IBAction func splitEditorRight(_ sender: Any?) {
        workspace?.editorManager?.splitActiveEditor(.trailing, workspace: workspace)
    }

    @IBAction func splitEditorDown(_ sender: Any?) {
        workspace?.editorManager?.splitActiveEditor(.bottom, workspace: workspace)
    }

    @IBAction func unsplitEditor(_ sender: Any?) {
        guard let manager = workspace?.editorManager else { return }
        manager.unsplit(manager.activeEditor)
    }

    @IBAction func unsplitAllEditors(_ sender: Any?) {
        workspace?.editorManager?.unsplitAll()
    }

    @IBAction func changeEditorSplitterOrientation(_ sender: Any?) {
        guard let manager = workspace?.editorManager else { return }
        manager.changeSplitterOrientation(of: manager.activeEditor)
    }

    @IBAction func gotoNextSplitter(_ sender: Any?) {
        guard let manager = workspace?.editorManager,
              let next = manager.nextSplitEditor(after: manager.activeEditor) else { return }
        manager.activeEditor = next
    }

    @IBAction func gotoPreviousSplitter(_ sender: Any?) {
        guard let manager = workspace?.editorManager,
              let previous = manager.previousSplitEditor(before: manager.activeEditor) else { return }
        manager.activeEditor = previous
    }
}
