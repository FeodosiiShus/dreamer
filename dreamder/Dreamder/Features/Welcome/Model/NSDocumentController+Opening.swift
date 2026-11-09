import AppKit

extension AppDocumentControlling {
    func openDocument(
        at url: URL,
        onCompletion: @MainActor @escaping () -> Void = {},
        onError: @MainActor @escaping (Error) -> Void = { _ in }
    ) {
        openDocument(withContentsOf: url, display: true) { _, _, error in
            MainActor.assumeIsolated {
                if let error {
                    NSAlert(error: error).runModal()
                    onError(error)
                } else {
                    NSApp.activate()
                    onCompletion()
                }
            }
        }
    }

    func openDocument(
        onCompletion: @MainActor @escaping (NSDocument?, Bool) -> Void,
        onCancel: @MainActor @escaping () -> Void,
        panels: any FilePanelPresenting = SystemFilePanels()
    ) {
        let request = OpenPanelRequest(
            title: "Open Workspace or File",
            canChooseFiles: true,
            canChooseDirectories: true
        )
        guard let url = panels.chooseFiles(request).first else {
            onCancel()
            return
        }
        openDocument(withContentsOf: url, display: true) { document, documentWasAlreadyOpen, error in
            MainActor.assumeIsolated {
                if let error {
                    NSAlert(error: error).runModal()
                    return
                }
                guard let document else {
                    let alert = NSAlert()
                    alert.messageText = NSLocalizedString(
                        "Failed to get document",
                        comment: "Failed to get document"
                    )
                    alert.runModal()
                    return
                }
                onCompletion(document, documentWasAlreadyOpen)
            }
        }
    }
}
