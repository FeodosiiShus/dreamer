import AppKit

extension DreamderWindowController {
    @IBAction func reformatCode(_ sender: Any?) {
        guard let codeFile = getSelectedCodeFile() else { return }
        Task { @MainActor in
            await FormattingService().reformatCode(codeFile)
        }
    }

    @IBAction func optimizeImports(_ sender: Any?) {
        guard let codeFile = getSelectedCodeFile() else { return }
        Task { @MainActor in
            await OptimizeImports().run(codeFile)
        }
    }

    func saveAfterFormatting(_ codeFile: CodeFileDocument, formatOnSave: FormatOnSave = .live()) {
        Task { @MainActor in
            await formatOnSave.run(for: codeFile)
            codeFile.save(nil)
            self.workspace?.editorManager?.activeEditor.temporaryTab = nil
        }
    }
}
