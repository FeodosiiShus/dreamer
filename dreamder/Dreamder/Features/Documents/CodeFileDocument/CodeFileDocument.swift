//
//  CodeFileDocument.swift
//  DreamderModules/CodeFile
//
//  Created by Rehatbir Singh on 12/03/2022.
//

import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import CodeEditSourceEditor
import CodeEditTextView
import CodeEditLanguages
import OSLog
import TextStory

enum CodeFileError: Error {
    case failedToDecode
    case failedToEncode
    case fileTypeError
    case readOnly
}

@objc(CodeFileDocument)
@Observable
final class CodeFileDocument: NSDocument {
    struct OpenOptions {
        let cursorPositions: [CursorPosition]
    }

    nonisolated static let logger = Logger(subsystem: "dev.dreamder.Dreamder", category: "CodeFileDocument")

    /// Sent when the document is opened. The document will be sent in the notification's object.
    nonisolated static let didOpenNotification = Notification.Name(rawValue: "CodeFileDocument.didOpen")
    /// Sent when the document is closed. The document's `fileURL` will be sent in the notification's object.
    nonisolated static let didCloseNotification = Notification.Name(rawValue: "CodeFileDocument.didClose")

    /// The text content of the document, stored as a text storage
    ///
    /// This is intentionally not a `@Published` variable. If it were published, SwiftUI would do a string
    /// compare each time the contents are updated, which could cause a hang on each keystroke if the file is large
    /// enough.
    ///
    /// To receive notifications for content updates, subscribe to one of the publishers on ``contentCoordinator``.
    @ObservationIgnored var content: NSTextStorage?

    /// The string encoding of the original file. Used to save the file back to the encoding it was loaded from.
    @ObservationIgnored var sourceEncoding: FileEncoding?

    /// The coordinator to use to subscribe to edit events and cursor location events.
    /// See ``CodeEditSourceEditor/CombineCoordinator``.
    var contentCoordinator: CombineCoordinator = CombineCoordinator()

    /// Used to override detected languages.
    var language: CodeLanguage?

    /// Document-specific overridden indent option.
    var indentOption: SettingsData.TextEditingSettings.IndentOption?

    /// Document-specific overridden tab width.
    var defaultTabWidth: Int?

    /// Document-specific overridden line wrap preference.
    var wrapLines: Bool?

    private(set) var contentState = CodeFileContentState()

    private(set) var editorConfig: EditorConfigProperties = .empty

    private(set) var detectedIndent: DetectedIndent?

    @ObservationIgnored weak var attachedController: TextViewController?

    var attachedTextView: TextView? {
        attachedController?.textView
    }

    @ObservationIgnored private(set) lazy var textViewBinder = CodeFileTextViewBinder(document: self)

    @ObservationIgnored var modifiedLineTracker = ModifiedLineTracker()

    @ObservationIgnored var retainedModifiedLines = IndexSet()

    @ObservationIgnored var pendingRemovedLineBreaks = 0

    @ObservationIgnored var isApplyingSaveActions = false

    /// Set up by ``LanguageServer``, conforms this type to ``LanguageServerDocument``.
    var languageServerObjects: LanguageServerDocumentObjects<CodeFileDocument> = .init()

    /// The type of data this file document contains.
    ///
    /// If its text content is not nil, a `text` UTType is returned.
    ///
    /// - Note: The UTType doesn't necessarily mean the file extension, it can be the MIME
    /// type or any other form of data representation.
    var utType: UTType? {
        if content != nil || contentState.readError != nil {
            return .text
        }

        guard let fileType, let type = UTType(fileType) else {
            return nil
        }

        return type
    }

    /// Specify options for opening the file such as the initial cursor positions.
    /// Nulled by ``CodeFileView`` on first load.
    @ObservationIgnored var openOptions: OpenOptions?

    private(set) var isEdited = false

    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    private nonisolated static let autosaveDelay: Duration = .seconds(2)

    @ObservationIgnored var autosavingInPlace: @MainActor () -> Bool = { CodeFileDocument.autosavesInPlace }

    @ObservationIgnored var closeConfirmation: (@MainActor (CodeFileDocument, @escaping (Bool) -> Void) -> Void)?

    deinit {
        autosaveTask?.cancel()
    }

    // MARK: - NSDocument

    nonisolated override static var autosavesInPlace: Bool {
        AutosavePreference.isEnabled.withLock { $0 }
    }

    nonisolated override var autosavingFileType: String? {
        Self.autosavesInPlace ? fileType : nil
    }

    override func makeWindowControllers() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        let windowController = NSWindowController(window: window)
        let needsCentering = fileURL.map { !Self.hasSavedWindowFrame(for: $0) } ?? false
        if let fileURL {
            windowController.shouldCascadeWindows = false
            windowController.windowFrameAutosaveName = fileURL.path
        }
        addWindowController(windowController)

        window.contentView = NSHostingView(rootView: SettingsInjector {
            WindowCodeFileView(codeFile: self)
        })

        window.makeKeyAndOrderFront(nil)

        if needsCentering {
            window.center()
        }
    }

    static func hasSavedWindowFrame(for url: URL, defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: "NSWindow Frame \(url.path)") != nil
    }

    // MARK: - Data

    override func data(ofType _: String) throws -> Data {
        guard !contentState.isReadOnly else {
            throw CodeFileError.readOnly
        }
        guard let sourceEncoding, let data = (content?.string as NSString?)?.data(using: sourceEncoding.nsValue) else {
            Self.logger.error("Failed to encode contents to \(self.sourceEncoding.debugDescription)")
            throw CodeFileError.failedToEncode
        }
        return data
    }

    // MARK: - Read

    /// This function is used for decoding files.
    /// It should not throw error as unsupported files can still be opened by QLPreviewView.
    nonisolated override func read(from data: Data, ofType typeName: String) throws {
        let load = CodeFileContentLoad.classify(data: data, fileTypeName: typeName)
        let detectedIndent = load.state.isReadOnly ? nil : load.text.flatMap { IndentDetector.detect(in: $0) }
        MainActor.assumeIsolated {
            apply(load, detectedIndent: detectedIndent)
        }
    }

    private func apply(_ load: CodeFileContentLoad, detectedIndent: DetectedIndent?) {
        sourceEncoding = load.encoding
        contentState = load.state
        self.detectedIndent = detectedIndent
        modifiedLineTracker.reset()
        retainedModifiedLines = IndexSet()
        editorConfig = fileURL.map { EditorConfigResolver().properties(for: $0) } ?? .empty
        if let text = load.text {
            if let content {
                registerContentChangeUndo(fileURL: fileURL, nsString: text as NSString, content: content)
                content.mutableString.setString(text)
            } else {
                content = CodeTextStorage(string: text)
            }
        } else {
            content = nil
        }
        guard load.text != nil, !load.state.isReadOnly else { return }
        NotificationCenter.default.post(name: Self.didOpenNotification, object: self)
    }

    // MARK: - Autosave

    /// Triggered when change occurred
    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)

        if autosavingInPlace() {
            return
        }

        isEdited = isDocumentEdited
    }

    /// Triggered when changes saved
    override func updateChangeCount(withToken changeCountToken: Any, for saveOperation: NSDocument.SaveOperationType) {
        super.updateChangeCount(withToken: changeCountToken, for: saveOperation)
        modifiedLineTracker.reset(keeping: retainedModifiedLines)
        retainedModifiedLines = IndexSet()

        if autosavingInPlace() {
            return
        }

        isEdited = isDocumentEdited
    }

    /// If ``hasUnautosavedChanges`` is `true` and an autosave has not already been scheduled, schedules a new autosave.
    /// If ``hasUnautosavedChanges`` is `false`, cancels any scheduled timers and returns.
    ///
    /// All operations are done with the ``autosaveTimerLock`` acquired (including the scheduled autosave) to ensure
    /// correct timing when scheduling or cancelling timers.
    override func scheduleAutosaving() {
        guard autosavingInPlace(), hasUnautosavedChanges else {
            autosaveTask?.cancel()
            autosaveTask = nil
            return
        }
        guard autosaveTask == nil else { return }
        autosaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: CodeFileDocument.autosaveDelay)
            guard !Task.isCancelled, let self else { return }
            autosaveTask = nil
            applySaveActions()
            autosave(withDelegate: nil, didAutosave: nil, contextInfo: nil)
        }
    }

    // MARK: - External Changes

    /// Handle the notification that the represented file item changed.
    ///
    /// We check if a file has been modified and can be read again to display to the user.
    /// To determine if a file has changed, we check the modification date. If it's different from the stored one,
    /// we continue.
    /// To determine if we can reload the file, we check if the document has outstanding edits. If not, we reload the
    /// file.
    nonisolated override func presentedItemDidChange() {
        if Thread.isMainThread {
            MainActor.assumeIsolated { handlePresentedItemChange() }
        } else {
            Task { @MainActor in
                self.handlePresentedItemChange()
            }
        }
    }

    // MARK: - Close

    override func close() {
        autosaveTask?.cancel()
        autosaveTask = nil
        super.close()
        NotificationCenter.default.post(name: Self.didCloseNotification, object: fileURL)
    }

    override func save(_ sender: Any?) {
        applySaveActions()

        do {
            if let directory = fileURL?.deletingLastPathComponent() {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }

            super.save(sender)
        } catch {
            presentError(error)
        }
    }

    override func save(
        withDelegate delegate: Any?,
        didSave didSaveSelector: Selector?,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        applySaveActions()
        super.save(withDelegate: delegate, didSave: didSaveSelector, contextInfo: contextInfo)
    }

    override func canClose(
        withDelegate delegate: Any,
        shouldClose shouldCloseSelector: Selector?,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        guard isDocumentEdited, let closeConfirmation, let shouldCloseSelector,
              let receiver = delegate as? NSObject
        else {
            super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
            return
        }
        closeConfirmation(self) { shouldClose in
            DocumentCloseCallback.invoke(
                on: receiver,
                selector: shouldCloseSelector,
                document: self,
                shouldClose: shouldClose,
                contextInfo: contextInfo
            )
        }
    }

    nonisolated override func fileNameExtension(
        forType typeName: String,
        saveOperation: NSDocument.SaveOperationType
    ) -> String? {
        guard let fileTypeName = Self.fileTypeExtension[typeName] else {
            return super.fileNameExtension(forType: typeName, saveOperation: saveOperation)
        }
        return fileTypeName
    }

    @ObservationIgnored var globalIndentOverride: GlobalIndent?
}

// MARK: LanguageServerDocument

extension CodeFileDocument: LanguageServerDocument {
    /// A stable string to use when identifying documents with language servers.
    /// Needs to be a valid URI, so always returns with the `file://` prefix to indicate it's a file URI.
    var languageServerURI: String? {
        fileURL?.lspURI
    }
}

private extension CodeFileDocument {

    nonisolated static let fileTypeExtension: [String: String?] = [
        "public.make-source": nil
    ]
}
