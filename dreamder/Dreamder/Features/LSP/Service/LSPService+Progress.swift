import Foundation
import LanguageServerProtocol

extension LSPService {
    static func workDoneProgressTaskID(for token: ProgressToken, key: ClientKey) -> String {
        let tokenID: String
        switch token {
        case let .optionA(number):
            tokenID = "int:\(number)"
        case let .optionB(text):
            tokenID = "string:\(text)"
        }
        return "lsp.progress.\(key.languageId.rawValue).\(key.workspacePath).\(tokenID)"
    }

    func publishWorkDoneProgress(
        _ update: LSPWorkDoneProgressUpdate,
        for token: ProgressToken,
        client: LanguageServerType,
        key: ClientKey
    ) {
        let taskID = Self.workDoneProgressTaskID(for: token, key: key)
        let progress = client.workDoneProgress.progress(for: token)
        let model = TaskNotificationModel(
            id: taskID,
            title: progress?.title ?? "",
            message: progress?.message,
            percentage: progress?.percentage.map { Double($0) / 100 },
            isLoading: true
        )
        switch update {
        case .began:
            postTaskNotification(.create, model: model, key: key)
        case .reported:
            postTaskNotification(.update, model: model, key: key)
        case .ended:
            postTaskNotification(.delete, model: model, key: key)
        case .ignored:
            return
        }
    }

    func discardWorkDoneProgress(of client: LanguageServerType, key: ClientKey) {
        for progress in client.workDoneProgress.activeProgresses {
            let taskID = Self.workDoneProgressTaskID(for: progress.token, key: key)
            postTaskNotification(.delete, model: TaskNotificationModel(id: taskID, title: ""), key: key)
        }
        client.workDoneProgress.shutDown()
    }

    private func postTaskNotification(
        _ action: TaskNotificationHandler.Action,
        model: TaskNotificationModel,
        key: ClientKey
    ) {
        let rootURL = URL(fileURLWithPath: key.workspacePath)
        guard let workspaceURL = LSPDiagnosticsPublisher.workspace(
            containing: rootURL,
            workspacePath: key.workspacePath
        )?.fileURL else {
            return
        }
        dependencies.postTask(workspaceURL, action, model)
    }
}
