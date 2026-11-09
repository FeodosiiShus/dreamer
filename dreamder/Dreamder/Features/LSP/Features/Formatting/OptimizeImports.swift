import AppKit
import Foundation
import LanguageServerProtocol

@MainActor
struct OptimizeImports {
    enum Outcome: Equatable {
        case applied
        case noActions
        case unavailable
        case failed
    }

    var lspService: () -> LSPService?
    var reportUnavailable: () -> Void

    init(
        lspService: @escaping () -> LSPService? = { .shared },
        reportUnavailable: @escaping () -> Void = { NSSound.beep() }
    ) {
        self.lspService = lspService
        self.reportUnavailable = reportUnavailable
    }

    @discardableResult
    func run(_ codeFile: CodeFileDocument) async -> Outcome {
        guard !codeFile.isReadOnly,
              let fileURL = codeFile.fileURL,
              let text = codeFile.content?.string,
              let client = lspService()?.languageClient(forDocument: fileURL) else {
            reportUnavailable()
            return .unavailable
        }
        let request = CodeActionRequest(
            client: client,
            documentURI: fileURL.lspURI,
            range: FormattingTextPositions.wholeDocumentRange(of: text),
            diagnostics: []
        )
        let groups = await request.fetch(only: [CodeActionKind.SourceOrganizeImports])
        guard let action = groups.allActions.first else { return .noActions }
        return await request.perform(action) ? .applied : .failed
    }
}
