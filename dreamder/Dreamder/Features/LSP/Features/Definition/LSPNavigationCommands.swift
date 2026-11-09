import Foundation

nonisolated enum LSPNavigationOutcome: Equatable, Sendable {
    case unavailable
    case missingServer
    case usages
    case message(String)
    case jumped(LSPNavigationDestination)
    case chooser(rowCount: Int)
}

@MainActor
struct LSPNavigationEnvironment {
    var resolveContext: @MainActor (WorkspaceDocument?) -> LSPEditorContextResult
    var showUsages: @MainActor (DreamderWindowController) -> Void

    static let live = LSPNavigationEnvironment(
        resolveContext: { LSPEditorContextResolver.resolve(workspace: $0) },
        showUsages: { ShowUsagesController.present(in: $0) }
    )
}

@MainActor
enum LSPNavigationCommands {
    private(set) static var pendingNavigation: Task<Void, Never>?

    static func goToDefinition(workspace: WorkspaceDocument?, typeDeclaration: Bool) {
        start(typeDeclaration ? .typeDeclaration : .declaration, in: workspace)
    }

    static func goToImplementation(workspace: WorkspaceDocument?) {
        start(.implementation, in: workspace)
    }

    @discardableResult
    static func goToDefinitionAsync(
        workspace: WorkspaceDocument?,
        typeDeclaration: Bool,
        environment: LSPNavigationEnvironment = .live
    ) async -> LSPNavigationOutcome {
        await navigate(
            kind: typeDeclaration ? .typeDeclaration : .declaration,
            workspace: workspace,
            environment: environment
        )
    }

    @discardableResult
    static func goToImplementationAsync(
        workspace: WorkspaceDocument?,
        environment: LSPNavigationEnvironment = .live
    ) async -> LSPNavigationOutcome {
        await navigate(kind: .implementation, workspace: workspace, environment: environment)
    }

    private static func start(_ kind: LSPNavigationKind, in workspace: WorkspaceDocument?) {
        pendingNavigation = Task { @MainActor in
            _ = await navigate(kind: kind, workspace: workspace, environment: .live)
        }
    }

    private static func navigate(
        kind: LSPNavigationKind,
        workspace: WorkspaceDocument?,
        environment: LSPNavigationEnvironment
    ) async -> LSPNavigationOutcome {
        switch environment.resolveContext(workspace) {
        case .unavailable:
            return .unavailable
        case .missingServer:
            present(in: workspace) { controller in
                DefinitionChooserPanelHost.shared.showMessage(
                    kind.missingServerMessage,
                    title: kind.commandName,
                    in: controller
                )
            }
            return .missingServer
        case .ready(let context):
            return await navigate(kind: kind, context: context, environment: environment)
        }
    }

    private static func navigate(
        kind: LSPNavigationKind,
        context: LSPEditorContext,
        environment: LSPNavigationEnvironment
    ) async -> LSPNavigationOutcome {
        let targets = await context.client.navigationTargets(
            for: kind,
            uri: context.documentURI,
            position: context.position
        )
        let origin = LSPNavigationOrigin(fileURL: context.fileURL.standardizedFileURL, position: context.position)
        switch LSPNavigationPlanner.plan(kind: kind, targets: targets, origin: origin) {
        case .showUsages:
            present(in: context.workspace) { environment.showUsages($0) }
            return .usages
        case .showMessage(let message):
            present(in: context.workspace) { controller in
                DefinitionChooserPanelHost.shared.showMessage(message, title: kind.commandName, in: controller)
            }
            return .message(message)
        case .jump(let destination):
            LSPDefinitionNavigator.jump(to: destination, in: context.workspace)
            return .jumped(destination)
        case .choose(let destinations):
            let rows = await LSPNavigationRowLoader.rows(for: destinations, context: context)
            present(in: context.workspace) { controller in
                DefinitionChooserPanelHost.shared.show(rows: rows, kind: kind, in: controller)
            }
            return .chooser(rowCount: rows.count)
        }
    }

    private static func present(
        in workspace: WorkspaceDocument?,
        _ body: (DreamderWindowController) -> Void
    ) {
        guard let controller = workspace?.windowControllers.first as? DreamderWindowController else { return }
        body(controller)
    }
}

@MainActor
enum LSPNavigationRowLoader {
    static func rows(
        for destinations: [LSPNavigationDestination],
        context: LSPEditorContext
    ) async -> [LSPUsageRow] {
        var texts: [String: String] = [context.documentURI: context.documentText]
        var urls: [String: URL] = [:]
        for destination in destinations {
            urls[destination.uri] = destination.fileURL
        }
        if let tabs = context.workspace.editorManager?.activeEditor.tabs {
            for tab in tabs {
                let uri = tab.file.url.lspURI
                guard urls[uri] != nil, texts[uri] == nil,
                      let content = tab.file.fileDocument?.content?.string else {
                    continue
                }
                texts[uri] = content
            }
        }
        for (uri, url) in urls where texts[uri] == nil {
            if let text = await readText(at: url) {
                texts[uri] = text
            }
        }
        return LSPUsagesMapping.rows(
            from: LSPNavigationPlanner.locations(for: destinations),
            fileTexts: texts,
            workspacePath: context.workspace.fileURL?.absolutePath
        )
    }

    @concurrent
    private static func readText(at url: URL) async -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }
}
