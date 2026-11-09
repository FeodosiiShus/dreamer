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

    var registeredUndoManager: CEUndoManager? {
        fileURL.flatMap { findWorkspace()?.undoRegistration.managerIfExists(forFile: $0) }
    }

    func discardRegisteredUndoManager() {
        guard let fileURL else { return }
        findWorkspace()?.undoRegistration.removeManager(forFile: fileURL)
    }

    static func open(
        contentsOf url: URL,
        ofType typeName: String,
        loader: CodeFileDiskLoader.Loader = CodeFileDiskLoader.live
    ) async throws -> CodeFileDocument {
        let modifiedAt = Self.modificationDate(at: url)
        let loaded = try await loader(url, typeName)
        let document = CodeFileDocument()
        document.fileType = typeName
        document.fileURL = url
        document.fileModificationDate = modifiedAt
        document.apply(loaded)
        return document
    }

    static func loading(
        contentsOf url: URL,
        ofType typeName: String,
        loader: @escaping CodeFileDiskLoader.Loader,
        onFailure: @escaping @MainActor (any Error) -> Void
    ) -> CodeFileDocument {
        let document = CodeFileDocument()
        document.fileType = typeName
        document.fileURL = url
        document.beginLoading(from: url, ofType: typeName, loader: loader, onFailure: onFailure)
        return document
    }

    private func beginLoading(
        from url: URL,
        ofType typeName: String,
        loader: @escaping CodeFileDiskLoader.Loader,
        onFailure: @escaping @MainActor (any Error) -> Void
    ) {
        isLoading = true
        let modifiedAt = Self.modificationDate(at: url)
        loadTask = Task { @MainActor [weak self] in
            let outcome: Result<CodeFileLoadedContent, any Error>
            do {
                outcome = .success(try await loader(url, typeName))
            } catch {
                outcome = .failure(error)
            }
            guard !Task.isCancelled, let self else { return }
            loadTask = nil
            switch outcome {
            case .success(let loaded):
                finishLoading(loaded, from: url, modifiedAt: modifiedAt)
            case .failure(let error):
                Self.logger.error("Error opening file: \(error)")
                isLoading = false
                onFailure(error)
                close()
            }
        }
    }

    private func finishLoading(_ loaded: CodeFileLoadedContent, from url: URL, modifiedAt: Date?) {
        fileModificationDate = modifiedAt
        apply(loaded)
        isLoading = false
        if Self.modificationDate(at: url) != modifiedAt {
            handlePresentedItemChange()
        }
    }

    func handlePresentedItemChange() {
        guard !isLoading else { return }
        guard let fileURL, let fileType,
              case let modifiedAt = Self.modificationDate(at: fileURL),
              fileModificationDate != modifiedAt, !isDocumentEdited else {
            super.presentedItemDidChange()
            return
        }
        reloadTask?.cancel()
        let loader = diskLoader
        reloadTask = Task { @MainActor [weak self] in
            guard let loaded = try? await loader(fileURL, fileType) else { return }
            guard !Task.isCancelled, let self, !isDocumentEdited else { return }
            reloadTask = nil
            fileModificationDate = modifiedAt
            apply(loaded)
        }
    }

    /// Helper to find the last modified date of the represented file item.
    /// 
    /// Different from `NSDocument.fileModificationDate`. This returns the *current* modification date, whereas the
    /// alternative stores the date that existed when we last read the file.
    private static func modificationDate(at url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.absolutePath)[.modificationDate] as? Date
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
