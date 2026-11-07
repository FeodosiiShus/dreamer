//
//  UtilityAreaOutputSourcePicker.swift
//  Dreamder
//
//  Created by Khan Winter on 7/18/25.
//

import SwiftUI

struct UtilityAreaOutputSourcePicker: View {
    typealias Sources = UtilityAreaOutputView.Sources

    @Environment(WorkspaceDocument.self) private var workspace

    @AppSettings(\.developerSettings.showInternalDevelopmentInspector)
    var showInternalDevelopmentInspector

    @Binding var selectedSource: Sources?

    private let extensionManager = ExtensionManager.shared

    @Service var lspService: LSPService

    var body: some View {
        Picker("Output Source", selection: $selectedSource) {
            if selectedSource == nil {
                Text("No Selected Output Source")
                    .italic()
                    .tag(Sources?.none)
                Divider()
            }

            if languageServerClients.isEmpty {
                Text("No Language Servers")
            } else {
                ForEach(languageServerClients, id: \.languageId) { server in
                    Text(Sources.languageServer(server.logContainer).title)
                        .tag(Sources.languageServer(server.logContainer))
                }
            }

            Divider()

            if extensionManager.extensions.isEmpty {
                Text("No Extensions")
            } else {
                ForEach(extensionManager.extensions) { extensionInfo in
                    Text(Sources.extensions(.init(extensionInfo: extensionInfo)).title)
                        .tag(Sources.extensions(.init(extensionInfo: extensionInfo)))
                }
            }

            if showInternalDevelopmentInspector {
                Divider()
                Text(Sources.devOutput.title)
                    .tag(Sources.devOutput)
            }
        }
        .id(pickerIdentity)
        .buttonStyle(.borderless)
        .labelsHidden()
        .controlSize(.small)
        .onChange(of: clientContainerIdentities, initial: true) {
            selectFirstSourceIfNeeded()
        }
    }

    private var languageServerClients: [LSPService.LanguageServerType] {
        lspService.languageClients
            .compactMap { (key, value) in
                if key.workspacePath == workspace.fileURL?.absolutePath {
                    return value
                }
                return nil
            }
            .sorted(by: { $0.languageId.rawValue < $1.languageId.rawValue })
    }

    private var clientContainerIdentities: [ObjectIdentifier] {
        languageServerClients.map { ObjectIdentifier($0.logContainer) }
    }

    private var pickerIdentity: [AnyHashable] {
        clientContainerIdentities.map { AnyHashable($0) }
        + extensionManager.extensions.map { AnyHashable($0.id) }
    }

    private func selectFirstSourceIfNeeded() {
        if selectedSource == nil, let client = languageServerClients.first {
            selectedSource = Sources.languageServer(client.logContainer)
        }
    }
}
