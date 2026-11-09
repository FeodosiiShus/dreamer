import Foundation
import LanguageClient
import LanguageServerProtocol
import SwiftUI

extension LSPService {
    struct Dependencies {
        var createServer: @MainActor (LSPLanguage, LanguageServerBinary, String) async throws -> LanguageServerType
        var discoverBinary: @MainActor (LSPLanguage, String) async -> LanguageServerBinary?
        var restartBackoff: Duration
        var observesDocumentNotifications: Bool
        var notifications: @MainActor () -> NotificationManager
        var openSettings: @MainActor () -> Void
        var runAlert: @MainActor (NSAlert) -> NSApplication.ModalResponse = { alert in
            Dependencies.presentAlert(alert, headless: DreamderHeadless.isEnabled)
        }
        var openExternalURL: @MainActor (URL) -> Bool = { url in
            Dependencies.openURL(url, headless: DreamderHeadless.isEnabled)
        }
        var postTask: @MainActor (URL, TaskNotificationHandler.Action, TaskNotificationModel) -> Void =
            { workspaceURL, action, model in
                TaskNotificationHandler.postTask(toWorkspace: workspaceURL, action: action, model: model)
            }

        static var live: Dependencies {
            Dependencies(
                createServer: { language, binary, workspacePath in
                    try await LanguageServerType.createServer(
                        for: language,
                        with: binary,
                        workspacePath: workspacePath,
                        workspaceTrusted: WorkspaceTrust.shared.isTrusted(URL(fileURLWithPath: workspacePath))
                    )
                },
                discoverBinary: { language, workspacePath in
                    let registry = RegistryManager.shared
                    let disabledPackages = Dependencies.disabledPackageNames(in: registry.installedLanguageServers)
                    return await LanguageServerDiscovery.binary(
                        for: language,
                        workspacePath: workspacePath,
                        workspaceTrusted: WorkspaceTrust.shared.isTrusted(URL(fileURLWithPath: workspacePath)),
                        registryInstallPath: registry.installPath.path,
                        disabledRegistryPackages: disabledPackages
                    )
                },
                restartBackoff: LSPService.restartBackoff,
                observesDocumentNotifications: true,
                notifications: { NotificationManager.shared },
                openSettings: { AppDelegate.openScene(.settings) }
            )
        }

        static func disabledPackageNames(in servers: [String: SettingsData.InstalledLanguageServer]) -> Set<String> {
            Set(servers.values.filter { !$0.isEnabled }.map(\.packageName))
        }

        static func presentAlert(_ alert: NSAlert, headless: Bool) -> NSApplication.ModalResponse {
            headless ? .abort : alert.runModal()
        }

        static func openURL(_ url: URL, headless: Bool) -> Bool {
            headless ? false : NSWorkspace.shared.open(url)
        }
    }
}
