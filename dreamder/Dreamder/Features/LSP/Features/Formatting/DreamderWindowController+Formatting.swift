import AppKit

extension DreamderWindowController {
    func makeFormattingService() -> FormattingService {
        let trust = workspaceTrust
        return FormattingService(isWorkspaceTrusted: { trust.isTrusted($0) })
    }

    @IBAction func reformatCode(_ sender: Any?) {
        guard let codeFile = getSelectedCodeFile() else { return }
        Task { @MainActor in
            await makeFormattingService().reformatCode(codeFile)
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
