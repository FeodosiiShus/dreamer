import AppKit
import CodeEditSourceEditor
import CodeEditTextView

final class EditorContextMenuCoordinator: NSObject, TextViewCoordinator {
    private static let f7KeyEquivalent = String(KeyNames.f7)

    private weak var controller: TextViewController?
    private let editorInstance: EditorInstance
    private let codeFile: CodeFileDocument
    private let pasteboard: any PasteboardAccess
    private let hasLanguageServer: (URL) -> Bool

    init(
        editorInstance: EditorInstance,
        codeFile: CodeFileDocument,
        pasteboard: any PasteboardAccess = SystemPasteboard(),
        hasLanguageServer: @escaping (URL) -> Bool = { url in
            LSPService.shared.languageClient(forDocument: url) != nil
        }
    ) {
        self.editorInstance = editorInstance
        self.codeFile = codeFile
        self.pasteboard = pasteboard
        self.hasLanguageServer = hasLanguageServer
        super.init()
    }

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
        EditorContextMenuInstaller.install()
        EditorContextMenuInstaller.setHandler(
            { [weak self] event in
                self?.menu(for: event)
            },
            for: controller.textView
        )
    }

    func destroy() {
        if let textView = controller?.textView {
            EditorContextMenuInstaller.removeHandler(for: textView)
        }
        controller = nil
    }

    private var fileURL: URL? {
        editorInstance.file.url
    }

    private func menu(for event: NSEvent) -> NSMenu? {
        guard let textView = controller?.textView, let url = fileURL else { return nil }
        moveCaretIfNeeded(for: event, in: textView)
        return buildMenu(for: url, textView: textView)
    }

    private func moveCaretIfNeeded(for event: NSEvent, in textView: TextView) {
        guard event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) else {
            return
        }
        let point = textView.convert(event.locationInWindow, from: nil)
        guard textView.bounds.contains(point) else { return }
        textView.window?.makeFirstResponder(textView)
        guard let offset = textView.layoutManager.textOffsetAtPoint(point) else { return }
        let isInsideSelection = textView.selectionManager.textSelections.contains { selection in
            !selection.range.isEmpty
                && offset >= selection.range.location
                && offset < selection.range.max
        }
        guard !isInsideSelection else { return }
        controller?.setCursorPositions([CursorPosition(range: NSRange(location: offset, length: 0))])
    }

    private func buildMenu(for url: URL, textView: TextView) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let workspace = codeFile.findWorkspace()
        let isEditable = textView.isEditable
        let hasSelection = textView.selectionManager.textSelections.contains { !$0.range.isEmpty }
        let hasLanguageServer = MainActor.assumeIsolated { languageServerAvailable(for: url) }

        menu.addItem(item("Cut", #selector(NSText.cut(_:)), "x", .command, enabled: isEditable && hasSelection))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), "c", .command, enabled: hasSelection))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), "v", .command, enabled: isEditable && canPaste()))

        let copyReference = NSMenuItem(title: "Copy Path/Reference", action: nil, keyEquivalent: "")
        copyReference.submenu = copyReferenceMenu(workspace: workspace)
        menu.addItem(copyReference)

        menu.addItem(.separator())

        let findInFiles = item(
            "Find in Files…",
            #selector(DreamderWindowController.openSearchNavigator(_:)),
            "f",
            [.command, .shift],
            enabled: workspace != nil
        )
        menu.addItem(findInFiles)

        let findUsages = item(
            "Find Usages",
            #selector(DreamderWindowController.findUsages(_:)),
            Self.f7KeyEquivalent,
            .option,
            enabled: hasLanguageServer
        )
        menu.addItem(findUsages)

        let showUsages = item(
            "Show Usages",
            #selector(DreamderWindowController.showUsages(_:)),
            Self.f7KeyEquivalent,
            [.option, .command],
            enabled: hasLanguageServer
        )
        menu.addItem(showUsages)

        let goTo = NSMenuItem(title: "Go To", action: nil, keyEquivalent: "")
        goTo.submenu = goToMenu(enabled: hasLanguageServer)
        menu.addItem(goTo)

        let quickDocumentation = item(
            "Quick Documentation",
            #selector(DreamderWindowController.showQuickDocumentation(_:)),
            "j",
            .control,
            enabled: hasLanguageServer
        )
        menu.addItem(quickDocumentation)

        menu.addItem(.separator())

        let openIn = NSMenuItem(title: "Open In", action: nil, keyEquivalent: "")
        openIn.submenu = openInMenu(workspace: workspace)
        menu.addItem(openIn)

        if let git = gitMenu(workspace: workspace) {
            menu.addItem(git)
        }

        return menu
    }

    private func copyReferenceMenu(workspace: WorkspaceDocument?) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let absolute = item(
            "Absolute Path",
            #selector(copyAbsolutePath(_:)),
            "c",
            [.command, .shift],
            target: self
        )
        menu.addItem(absolute)

        let projectRelative = item(
            "Path From Project Root",
            #selector(copyProjectRelativePath(_:)),
            enabled: workspace?.workspaceFileManager?.folderUrl != nil,
            target: self
        )
        menu.addItem(projectRelative)

        let name = item("File Name", #selector(copyFileName(_:)), target: self)
        menu.addItem(name)
        return menu
    }

    private func goToMenu(enabled: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let declaration = item(
            "Declaration or Usages",
            #selector(goToDeclaration(_:)),
            "b",
            .command,
            enabled: enabled,
            target: self
        )
        menu.addItem(declaration)

        let typeDeclaration = item(
            "Type Declaration",
            #selector(goToTypeDeclaration(_:)),
            "b",
            [.command, .shift],
            enabled: enabled,
            target: self
        )
        menu.addItem(typeDeclaration)
        return menu
    }

    private func openInMenu(workspace: WorkspaceDocument?) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let finder = item("Finder", #selector(openInFinder(_:)), target: self)
        menu.addItem(finder)

        let terminal = item(
            "Terminal",
            #selector(openInTerminal(_:)),
            enabled: workspace != nil,
            target: self
        )
        menu.addItem(terminal)
        return menu
    }

    private func gitMenu(workspace: WorkspaceDocument?) -> NSMenuItem? {
        guard let sourceControlManager = workspace?.sourceControlManager,
              sourceControlManager.isGitRepository else {
            return nil
        }
        let blame = GitBlameCoordinator.coordinator(for: editorInstance)

        let menu = NSMenu(title: "Git")
        menu.autoenablesItems = false

        let annotate = item(
            "Annotate with Git Blame",
            #selector(toggleAnnotate(_:)),
            enabled: blame != nil,
            target: self
        )
        if blame?.isAnnotating == true {
            annotate.state = .on
        }
        menu.addItem(annotate)
        menu.addItem(item("Show Diff", #selector(showDiff(_:)), target: self))
        menu.addItem(item("Rollback…", #selector(rollbackFile(_:)), target: self))
        menu.addItem(item("Show History", #selector(showHistory(_:)), target: self))

        let root = NSMenuItem(title: "Git", action: nil, keyEquivalent: "")
        root.submenu = menu
        return root
    }

    private func item(
        _ title: String,
        _ action: Selector?,
        _ keyEquivalent: String = "",
        _ modifiers: NSEvent.ModifierFlags = .command,
        enabled: Bool = true,
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        if !keyEquivalent.isEmpty {
            item.keyEquivalentModifierMask = modifiers
        }
        item.target = target
        item.isEnabled = action == nil || enabled
        return item
    }

    private func canPaste() -> Bool {
        pasteboard.canReadPlainText
    }

    @MainActor
    private func languageServerAvailable(for url: URL) -> Bool {
        hasLanguageServer(url)
    }

    private func copyToPasteboard(_ string: String) {
        pasteboard.replaceContents(withText: string)
    }

    @objc private func copyAbsolutePath(_ sender: Any?) {
        guard let url = fileURL else { return }
        copyToPasteboard(url.path(percentEncoded: false))
    }

    @MainActor
    @objc private func copyProjectRelativePath(_ sender: Any?) {
        guard let url = fileURL,
              let root = codeFile.findWorkspace()?.workspaceFileManager?.folderUrl else { return }
        copyToPasteboard(Self.projectRelativePath(of: url, root: root))
    }

    static func projectRelativePath(of url: URL, root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let components = url.standardizedFileURL.pathComponents
        guard components.count > rootComponents.count,
              Array(components.prefix(rootComponents.count)) == rootComponents else {
            return url.path(percentEncoded: false)
        }
        return components.dropFirst(rootComponents.count).joined(separator: "/")
    }

    @objc private func copyFileName(_ sender: Any?) {
        guard let url = fileURL else { return }
        copyToPasteboard(url.lastPathComponent)
    }

    @MainActor
    @objc private func goToDeclaration(_ sender: Any?) {
        LSPNavigationCommands.goToDefinition(workspace: codeFile.findWorkspace(), typeDeclaration: false)
    }

    @MainActor
    @objc private func goToTypeDeclaration(_ sender: Any?) {
        LSPNavigationCommands.goToDefinition(workspace: codeFile.findWorkspace(), typeDeclaration: true)
    }

    @objc private func openInFinder(_ sender: Any?) {
        guard let url = fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @MainActor
    @objc private func openInTerminal(_ sender: Any?) {
        guard let url = fileURL, let workspace = codeFile.findWorkspace() else { return }
        workspace.utilityAreaModel?.addTerminal(rootURL: url.deletingLastPathComponent())
        workspace.toolWindowManager.show(.terminal)
    }

    @objc private func toggleAnnotate(_ sender: Any?) {
        GitBlameCoordinator.coordinator(for: editorInstance)?.toggleAnnotate()
    }

    @MainActor
    @objc private func showDiff(_ sender: Any?) {
        guard let url = fileURL, let workspace = codeFile.findWorkspace() else { return }
        DiffViewerPresenter.showFileDiff(workspace: workspace, fileURL: url)
    }

    @MainActor
    @objc private func showHistory(_ sender: Any?) {
        codeFile.findWorkspace()?.toolWindowManager.show(.git)
    }

    @MainActor
    @objc private func rollbackFile(_ sender: Any?) {
        guard let url = fileURL, let workspace = codeFile.findWorkspace() else { return }
        let alert = NSAlert()
        alert.messageText = "Rollback Changes"
        alert.informativeText = "Revert all changes in \"\(url.lastPathComponent)\" to the last committed version?"
        alert.addButton(withTitle: "Rollback")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let apply: (NSApplication.ModalResponse) -> Void = { [weak workspace] response in
            Self.confirmRollback(response, url: url, in: workspace)
        }
        if let window = controller?.view.window {
            alert.beginSheetModal(for: window, completionHandler: apply)
        } else {
            apply(alert.runModal())
        }
    }

    @MainActor
    static func confirmRollback(_ response: NSApplication.ModalResponse, url: URL, in workspace: WorkspaceDocument?) {
        guard response == .alertFirstButtonReturn else { return }
        workspace?.sourceControlManager?.discardChanges(for: url)
    }
}
