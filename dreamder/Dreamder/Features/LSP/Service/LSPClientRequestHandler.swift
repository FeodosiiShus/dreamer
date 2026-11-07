import Foundation
import JSONRPC
import LanguageServerProtocol

nonisolated struct LSPClientRequestEnvironment: Sendable {
    typealias WorkspaceFoldersProvider = @Sendable () async -> [WorkspaceFolder]
    typealias ConfigurationProvider = @Sendable (ConfigurationItem) async -> LSPAny?
    typealias EditApplier = @Sendable (ApplyWorkspaceEditParams) async -> ApplyWorkspaceEditResult
    typealias MessagePresenter = @Sendable (ShowMessageRequestParams) async -> MessageActionItem?
    typealias DocumentPresenter = @Sendable (ShowDocumentParams) async -> Bool
    typealias RefreshHandler = @Sendable (LSPRefreshKind) async -> Void

    var workspaceFolders: WorkspaceFoldersProvider
    var configuration: ConfigurationProvider
    var applyEdit: EditApplier
    var showMessage: MessagePresenter?
    var showDocument: DocumentPresenter
    var refresh: RefreshHandler

    init(
        workspaceFolders: @escaping WorkspaceFoldersProvider = { return [] },
        configuration: @escaping ConfigurationProvider = { _ in nil },
        applyEdit: @escaping EditApplier = { _ in
            ApplyWorkspaceEditResult(applied: false, failureReason: "The client cannot apply workspace edits")
        },
        showMessage: MessagePresenter? = nil,
        showDocument: @escaping DocumentPresenter = { _ in false },
        refresh: @escaping RefreshHandler = { _ in }
    ) {
        self.workspaceFolders = workspaceFolders
        self.configuration = configuration
        self.applyEdit = applyEdit
        self.showMessage = showMessage
        self.showDocument = showDocument
        self.refresh = refresh
    }
}

nonisolated struct LSPClientRequestHandler: Sendable {
    static let methodNotFoundCode = -32601
    static let internalErrorCode = -32603

    let environment: LSPClientRequestEnvironment
    let capabilities: LSPDynamicCapabilityRegistry
    let progress: LSPWorkDoneProgressTracker
    let repliesToCapabilityRegistration: Bool

    init(
        environment: LSPClientRequestEnvironment = LSPClientRequestEnvironment(),
        capabilities: LSPDynamicCapabilityRegistry = LSPDynamicCapabilityRegistry(),
        progress: LSPWorkDoneProgressTracker = LSPWorkDoneProgressTracker(),
        repliesToCapabilityRegistration: Bool = true
    ) {
        self.environment = environment
        self.capabilities = capabilities
        self.progress = progress
        self.repliesToCapabilityRegistration = repliesToCapabilityRegistration
    }

    func handle(_ request: ServerRequest) async {
        switch request {
        case let .workspaceConfiguration(params, reply):
            var values: [LSPAny] = []
            values.reserveCapacity(params.items.count)
            for item in params.items {
                values.append(await environment.configuration(item) ?? .null)
            }
            await reply(.success(values))

        case let .workspaceFolders(reply):
            let folders = await environment.workspaceFolders()
            await reply(.success(folders))

        case let .workspaceApplyEdit(params, reply):
            let result = await environment.applyEdit(params)
            await reply(.success(result))

        case let .clientRegisterCapability(params, reply):
            capabilities.register(params.registrations)
            if repliesToCapabilityRegistration {
                await reply(nil)
            }
            var refreshed: Set<LSPRefreshKind> = []
            for registration in params.registrations {
                guard let kind = LSPRefreshKind(registrationMethod: registration.method),
                      refreshed.insert(kind).inserted else {
                    continue
                }
                await environment.refresh(kind)
            }

        case let .clientUnregisterCapability(params, reply):
            capabilities.unregister(params.unregistrations)
            if repliesToCapabilityRegistration {
                await reply(nil)
            }

        case let .workspaceCodeLensRefresh(reply):
            await reply(nil)
            await environment.refresh(.codeLens)

        case let .workspaceSemanticTokenRefresh(reply):
            await reply(nil)
            await environment.refresh(.semanticTokens)

        case let .windowShowMessageRequest(params, reply):
            let chosen = await environment.showMessage?(params)
            await reply(.success(chosen))

        case let .windowShowDocument(params, reply):
            let success = await environment.showDocument(params)
            await reply(.success(ShowDocumentResult(success: success)))

        case let .windowWorkDoneProgressCreate(params, reply):
            progress.create(params.token)
            await reply(nil)

        case let .custom(method, _, reply):
            if let kind = LSPRefreshKind(refreshMethod: method) {
                await reply(.success(.null))
                await environment.refresh(kind)
            } else {
                let failure = Self.error(code: Self.methodNotFoundCode, message: "Method not found: \(method)")
                await reply(.failure(failure))
            }
        }
    }

    static func reject(
        _ request: ServerRequest,
        code: Int = LSPClientRequestHandler.internalErrorCode,
        message: String
    ) async {
        let failure = Self.error(code: code, message: message)
        switch request {
        case let .workspaceConfiguration(_, reply):
            await reply(.failure(failure))
        case let .workspaceFolders(reply):
            await reply(.failure(failure))
        case let .workspaceApplyEdit(_, reply):
            await reply(.failure(failure))
        case let .clientRegisterCapability(_, reply):
            await reply(failure)
        case let .clientUnregisterCapability(_, reply):
            await reply(failure)
        case let .workspaceCodeLensRefresh(reply):
            await reply(failure)
        case let .workspaceSemanticTokenRefresh(reply):
            await reply(failure)
        case let .windowShowMessageRequest(_, reply):
            await reply(.failure(failure))
        case let .windowShowDocument(_, reply):
            await reply(.failure(failure))
        case let .windowWorkDoneProgressCreate(_, reply):
            await reply(failure)
        case let .custom(_, _, reply):
            await reply(.failure(failure))
        }
    }

    private static func error(code: Int, message: String) -> AnyJSONRPCResponseError {
        AnyJSONRPCResponseError(code: code, message: message, data: nil)
    }
}
