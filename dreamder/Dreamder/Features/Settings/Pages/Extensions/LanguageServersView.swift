//
//  ExtensionsSettingsView.swift
//  Dreamder
//
//  Created by Abe Malla on 2/2/25.
//

import SwiftUI

@Observable
@MainActor
final class LanguageServersModel {
    let registryManager: RegistryManager
    let searchModel = FuzzySearchUIModel<RegistryItem>()
    var selectedInstall: PackageManagerInstallOperation?
    var searchText: String = "" {
        didSet {
            searchModel.searchTextUpdated(searchText: searchText, allItems: registryManager.registryItems)
        }
    }

    init(registryManager: RegistryManager) {
        self.registryManager = registryManager
    }

    func install(_ item: RegistryItem) {
        do {
            selectedInstall = try registryManager.installOperation(package: item)
        } catch {
            // Display the error
            NSAlert(error: error).runModal()
        }
    }
}

/// Displays a searchable list of packages from the ``RegistryManager``.
struct LanguageServersView: View {
    @State private var model: LanguageServersModel

    init(model: LanguageServersModel = LanguageServersModel(registryManager: .shared)) {
        _model = State(initialValue: model)
    }

    var body: some View {
        SettingsForm {
            if model.registryManager.isDownloadingRegistry {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
            }

            Section {
                List(model.searchModel.items ?? model.registryManager.registryItems, id: \.name) { item in
                    LanguageServerRowView(
                        package: item,
                        registryManager: model.registryManager,
                        onCancel: model.registryManager.cancelInstallation,
                        onInstall: model.install
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
                .searchable(text: $model.searchText)
            } header: {
                Label(
                    "Warning: Language server installation is experimental. Use at your own risk.",
                    systemImage: "exclamationmark.triangle.fill"
                )
            }
        }
        .sheet(item: $model.selectedInstall) { operation in
            LanguageServerInstallView(operation: operation, registryManager: model.registryManager)
        }
    }

    func getInfoString() -> AttributedString {
        let string = "Dreamder makes use of the Mason Registry for language server installation. To install a package, "
        + "Dreamder uses the package manager directed by the Mason Registry, and installs a copy of "
        + "the language server in Application Support.\n\n"
        + "Language server installation is still experimental, there may be bugs and expect this flow "
        + "to change over time."

        var attrString = AttributedString(string)

        if let linkRange = attrString.range(of: "Mason Registry") {
            attrString[linkRange].link = URL(string: "https://mason-registry.dev/")
            attrString[linkRange].foregroundColor = NSColor.linkColor
        }

        return attrString
    }
}
