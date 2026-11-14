import AppKit

struct DocumentRemovalContext {
    let lspService: LSPService
    let openDocuments: @MainActor () -> [NSDocument]
    let settings: Settings
    let showWelcomeWindow: @MainActor () -> Void
    let quitApplication: @MainActor () -> Void
}
