import AppKit
import Foundation
import CodeEditSourceEditor
import CodeEditTextView
import CodeEditLanguages
import TextStory

extension CodeFileDocument {
    var isReadOnly: Bool {
        contentState.isReadOnly
    }

    var isBinary: Bool {
        contentState.isBinary
    }

    var isTooLargeForIntelligence: Bool {
        contentState.isTooLargeForIntelligence
    }

    var readError: CodeFileReadError? {
        contentState.readError
    }

    var notice: CodeFileNotice? {
        contentState.notice
    }

    /// If this file is already open and being tracked by an undo manager, we register an undo mutation
    /// of the entire contents. This allows the user to undo changes that occurred outside of Dreamder
    /// while the file was displayed in Dreamder.
    ///
    /// - Note: This is inefficient memory-wise. We could do a diff of the file and only register the
    ///         mutations that would recreate the diff. However, that would instead be CPU intensive.
    ///         Tradeoffs.
    func registerContentChangeUndo(fileURL: URL?, nsString: NSString, content: NSTextStorage) {
        guard let fileURL else { return }
        // If there's an undo manager, register a mutation replacing the entire contents.
        let mutation = TextMutation(
            string: nsString as String,
            range: NSRange(location: 0, length: content.length),
            limit: content.length
        )
        let undoManager = self.findWorkspace()?.undoRegistration.managerIfExists(forFile: fileURL)
        undoManager?.registerMutation(mutation)
    }

    func handlePresentedItemChange() {
        guard !reloadFromDiskIfUnedited() else { return }
        super.presentedItemDidChange()
    }

    private func reloadFromDiskIfUnedited() -> Bool {
        guard fileModificationDate != getModificationDate(), !isDocumentEdited else { return false }
        fileModificationDate = getModificationDate()
        if let fileURL, let fileType {
            try? read(from: fileURL, ofType: fileType)
        }
        return true
    }

    /// Helper to find the last modified date of the represented file item.
    /// 
    /// Different from `NSDocument.fileModificationDate`. This returns the *current* modification date, whereas the
    /// alternative stores the date that existed when we last read the file.
    private func getModificationDate() -> Date? {
        guard let path = fileURL?.absolutePath else { return nil }
        return try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }

    /// Determines the code language of the document.
    /// Use ``CodeFileDocument/language`` for the default value before using this. That property is used to override
    /// the file's language.
    /// - Returns: The detected code language.
    func getLanguage() -> CodeLanguage {
        guard let url = fileURL else {
            return .default
        }
        return language ?? CodeLanguage.detectLanguageFrom(
            url: url,
            prefixBuffer: content?.string.getFirstLines(5),
            suffixBuffer: content?.string.getLastLines(5)
        )
    }

    static func currentGlobalIndent() -> GlobalIndent {
        let editing = Settings[\.textEditing]
        return GlobalIndent(
            style: editing.indentOption.indentType == .tab ? .tab : .spaces,
            spaceCount: editing.indentOption.spaceCount,
            tabWidth: editing.defaultTabWidth
        )
    }

    func resolveIndent(global: GlobalIndent) -> ResolvedIndent {
        let overrideStyle: IndentStyle? = indentOption.map { $0.indentType == .tab ? .tab : .spaces }
        return IndentResolver.resolve(
            documentOverride: IndentLayer(
                style: overrideStyle,
                spaceCount: indentOption?.spaceCount,
                tabWidth: defaultTabWidth
            ),
            editorConfig: editorConfig,
            detected: detectedIndent,
            languageDefault: LanguageIndentDefaults.layer(for: fileURL),
            global: global
        )
    }

    var resolvedIndent: ResolvedIndent {
        resolveIndent(global: globalIndentOverride ?? Self.currentGlobalIndent())
    }

    var effectiveIndentOption: SettingsData.TextEditingSettings.IndentOption {
        let resolved = resolvedIndent
        return SettingsData.TextEditingSettings.IndentOption(
            indentType: resolved.style == .tab ? .tab : .spaces,
            spaceCount: resolved.spaceCount
        )
    }

    var effectiveTabWidth: Int {
        resolvedIndent.tabWidth
    }

    func findWorkspace() -> WorkspaceDocument? {
        fileURL?.findWorkspace()
    }
}
