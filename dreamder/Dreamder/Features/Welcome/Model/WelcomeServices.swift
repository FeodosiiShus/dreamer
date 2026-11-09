import AppKit

struct WelcomeServices {
    var open: @MainActor (URL, @escaping @MainActor () -> Void) -> Void
    var newProject: @MainActor (@escaping @MainActor () -> Void) -> Void
    var openFromDisk: @MainActor (@escaping @MainActor () -> Void) -> Void
    var confirmRemoval: @MainActor (RecentProject) -> Bool
    var copyToClipboard: @MainActor (String) -> Void
    var reveal: @MainActor ([URL]) -> Void
    var dismiss: @MainActor () -> Void
    var makeCloneViewModel: @MainActor () -> GitCloneViewModel

    static let live = make(
        pasteboard: SystemPasteboard(),
        documents: { NSDocumentController.shared },
        panels: SystemFilePanels(),
        createDocument: createDocumentThroughSharedController
    )

    static func createDocumentThroughSharedController() async -> Bool {
        await (NSDocumentController.shared as? DreamderDocumentController)?.createAndOpenNewDocument() == true
    }

    static func make(
        pasteboard: any PasteboardAccess,
        documents: @escaping @MainActor () -> any AppDocumentControlling,
        panels: any FilePanelPresenting,
        createDocument: @escaping @MainActor () async -> Bool
    ) -> WelcomeServices {
        WelcomeServices(
            open: { url, completion in
                documents().openDocument(at: url, onCompletion: completion)
            },
            newProject: { completion in
                Task {
                    if await createDocument() { completion() }
                }
            },
            openFromDisk: { completion in
                documents().openDocument(onCompletion: { _, _ in completion() }, onCancel: {}, panels: panels)
            },
            confirmRemoval: { presentRemovalConfirmation(for: $0) },
            copyToClipboard: { pasteboard.replaceContents(withText: $0) },
            reveal: { NSWorkspace.shared.activateFileViewerSelecting($0) },
            dismiss: { closeWelcomeWindows() },
            makeCloneViewModel: { GitCloneViewModel() }
        )
    }

    static func closeWelcomeWindows() {
        NSApp.windows
            .filter { $0.identifier?.rawValue == SceneID.welcome.rawValue }
            .forEach { $0.close() }
    }

    static func presentRemovalConfirmation(for project: RecentProject) -> Bool {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Remove Recent Project", comment: "Welcome remove confirmation title")
        alert.informativeText = String(
            format: NSLocalizedString("Remove '%@' from recent projects list?", comment: "Welcome remove message"),
            project.displayName
        )
        alert.addButton(withTitle: NSLocalizedString("Remove", comment: "Welcome remove confirmation button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Welcome remove cancel button"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
