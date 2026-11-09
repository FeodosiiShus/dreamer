import AppKit
import CodeEditTextView
import Foundation
import LanguageServerProtocol
import OSLog

extension CodeFileDocument {
    var formattingOptions: FormattingOptions {
        let indent = effectiveIndentOption
        let usesTabs = indent.indentType == .tab
        return FormattingOptions(
            tabSize: max(usesTabs ? effectiveTabWidth : indent.spaceCount, 1),
            insertSpaces: !usesTabs
        )
    }
}

@MainActor
struct FormattingService {
    enum Outcome: Equatable {
        case applied
        case unchanged
        case unavailable
        case failed
    }

    private enum Strategy {
        case external(ExternalFormatter)
        case languageServer(LSPService.LanguageServerType, range: LSPRange?)
    }

    private struct Target {
        let textView: TextView
        let fileURL: URL
        let strategy: Strategy
    }

    static let logger = Logger(subsystem: "dev.dreamder.Dreamder", category: "Formatting")

    var lspService: () -> LSPService?
    var runner: any ProcessRunning
    var fileExists: @Sendable (String) -> Bool
    var workspaceRoot: (CodeFileDocument) -> URL?
    var isWorkspaceTrusted: (URL) -> Bool
    var processEnvironment: @Sendable () async -> [String: String]
    var reportFailure: (String) -> Void
    var reportUnavailable: () -> Void
    var externalTimeout: Duration

    init(
        lspService: @escaping () -> LSPService? = { .shared },
        runner: any ProcessRunning = ProcessRunner(),
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        workspaceRoot: @escaping (CodeFileDocument) -> URL? = { $0.findWorkspace()?.fileURL },
        isWorkspaceTrusted: @escaping (URL) -> Bool = { WorkspaceTrust.shared.isTrusted($0) },
        processEnvironment: @escaping @Sendable () async -> [String: String] = {
            await LSPProcessEnvironment.shared.resolve().environment
        },
        reportFailure: @escaping (String) -> Void = { Self.logger.warning("Formatting failed: \($0, privacy: .public)") },
        reportUnavailable: @escaping () -> Void = { NSSound.beep() },
        externalTimeout: Duration = ExternalFormatterRunner.defaultTimeout
    ) {
        self.lspService = lspService
        self.runner = runner
        self.fileExists = fileExists
        self.workspaceRoot = workspaceRoot
        self.isWorkspaceTrusted = isWorkspaceTrusted
        self.processEnvironment = processEnvironment
        self.reportFailure = reportFailure
        self.reportUnavailable = reportUnavailable
        self.externalTimeout = externalTimeout
    }

    func canFormatDocument(_ codeFile: CodeFileDocument) -> Bool {
        target(for: codeFile, selection: nil) != nil
    }

    func formatDocument(_ codeFile: CodeFileDocument) async -> Outcome {
        await perform(codeFile, selection: nil)
    }

    @discardableResult
    func reformatCode(_ codeFile: CodeFileDocument) async -> Outcome {
        let selection = codeFile.attachedTextView?.selectionManager.textSelections.first?.range
        let outcome = await perform(codeFile, selection: selection.flatMap { $0.length > 0 ? $0 : nil })
        if outcome == .unavailable {
            reportUnavailable()
        }
        return outcome
    }

    private func target(for codeFile: CodeFileDocument, selection: NSRange?) -> Target? {
        guard !codeFile.isReadOnly,
              let textView = codeFile.attachedTextView,
              textView.isEditable,
              let fileURL = codeFile.fileURL else {
            return nil
        }
        if let root = workspaceRoot(codeFile), isWorkspaceTrusted(root),
           let formatter = ExternalFormatterChooser.choose(
            root: root,
            fileURL: fileURL,
            selection: selection,
            fileExists: fileExists
           ) {
            return Target(textView: textView, fileURL: fileURL, strategy: .external(formatter))
        }
        guard let client = lspService()?.languageClient(forDocument: fileURL) else { return nil }
        guard let selection else {
            return client.supportsDocumentFormatting
                ? Target(textView: textView, fileURL: fileURL, strategy: .languageServer(client, range: nil))
                : nil
        }
        let range = FormattingTextPositions.range(of: selection, in: Array(textView.textStorage.string.utf16))
        return client.supportsRangeFormatting
            ? Target(textView: textView, fileURL: fileURL, strategy: .languageServer(client, range: range))
            : nil
    }

    private func perform(_ codeFile: CodeFileDocument, selection: NSRange?) async -> Outcome {
        guard let target = target(for: codeFile, selection: selection) else { return .unavailable }
        let original = target.textView.textStorage.string
        switch target.strategy {
        case .external(let formatter):
            return await applyExternal(formatter, to: target.textView, original: original)
        case .languageServer(let client, let range):
            return await applyLanguageServer(
                client,
                range: range,
                options: codeFile.formattingOptions,
                uri: target.fileURL.lspURI,
                to: target.textView,
                original: original
            )
        }
    }

    private func applyExternal(_ formatter: ExternalFormatter, to textView: TextView, original: String) async -> Outcome {
        let externalRunner = ExternalFormatterRunner(
            runner: runner,
            environment: await processEnvironment(),
            timeout: externalTimeout
        )
        switch await externalRunner.format(formatter, text: original) {
        case .failed(let message):
            reportFailure(message)
            return .failed
        case .formatted(let formatted):
            guard let edit = MinimalTextEdit.between(original, formatted) else { return .unchanged }
            guard isCurrent(textView, original) else { return .failed }
            WorkspaceEditApplier.apply([edit], to: textView)
            return .applied
        }
    }

    private func applyLanguageServer(
        _ client: LSPService.LanguageServerType,
        range: LSPRange?,
        options: FormattingOptions,
        uri: String,
        to textView: TextView,
        original: String
    ) async -> Outcome {
        do {
            let edits: [TextEdit]?
            if let range {
                edits = try await client.requestRangeFormatting(for: uri, range, withFormat: options)
            } else {
                edits = try await client.requestFormatting(for: uri, withFormat: options)
            }
            guard let edits, !edits.isEmpty else { return .unchanged }
            guard isCurrent(textView, original) else { return .failed }
            let applied = try await WorkspaceEditApplier(client: client).editOpenDocument(uri: uri, edits: edits)
            return applied ? .applied : .failed
        } catch {
            reportFailure("\(error)")
            return .failed
        }
    }

    private func isCurrent(_ textView: TextView, _ original: String) -> Bool {
        !Task.isCancelled && textView.textStorage.string == original
    }
}
