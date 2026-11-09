//
//  LanguageServerRowView.swift
//  Dreamder
//
//  Created by Abe Malla on 2/2/25.
//

import SwiftUI

private let iconSize: CGFloat = 26

@Observable
@MainActor
final class LanguageServerRowState {
    var isHovering: Bool
    var showMore: Bool
    var showingRemovalConfirmation = false
    var isRemoving = false
    var removalError: Error?
    var showingRemovalError = false

    init(isHovering: Bool = false, showMore: Bool = false) {
        self.isHovering = isHovering
        self.showMore = showMore
    }

    var removalErrorMessage: String {
        removalError?.localizedDescription ?? "An unknown error occurred"
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }

    func toggleShowMore() {
        showMore.toggle()
    }

    func requestRemoval() {
        showingRemovalConfirmation = true
    }

    func dismissRemovalConfirmation() {
        showingRemovalConfirmation = false
    }

    func dismissRemovalError() {
        showingRemovalError = false
    }

    func remove(packageName: String, using registryManager: RegistryManager) {
        isRemoving = true
        Task {
            do {
                try await registryManager.removeLanguageServer(packageName: packageName)
                isRemoving = false
            } catch {
                isRemoving = false
                removalError = error
                showingRemovalError = true
            }
        }
    }
}

struct LanguageServerRowView: View, Equatable {
    let package: RegistryItem
    let registryManager: RegistryManager
    let onCancel: (() -> Void)
    let onInstall: ((RegistryItem) async -> Void)

    private var isInstalled: Bool {
        registryManager.installedLanguageServers[package.name] != nil
    }
    private var isEnabled: Bool {
        registryManager.installedLanguageServers[package.name]?.isEnabled ?? false
    }

    @State private var model: LanguageServerRowState

    init(
        package: RegistryItem,
        registryManager: RegistryManager,
        model: LanguageServerRowState = LanguageServerRowState(),
        onCancel: @escaping (() -> Void),
        onInstall: @escaping (RegistryItem) async -> Void
    ) {
        self.package = package
        self.registryManager = registryManager
        self.onCancel = onCancel
        self.onInstall = onInstall
        _model = State(initialValue: model)
    }

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading) {
                    Text(package.sanitizedName)

                    ZStack(alignment: .leadingLastTextBaseline) {
                        VStack(alignment: .leading) {
                            Text(package.sanitizedDescription)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(model.showMore ? nil : 1)
                                .truncationMode(.tail)
                            if model.showMore {
                                Button(package.homepagePretty, action: openHomepage)
                                    .buttonStyle(.plain)
                                    .foregroundColor(Color(NSColor.linkColor))
                                    .font(.footnote)
                                    .cursor(.pointingHand)
                                if let installerName = package.installMethod?.packageManagerType?.rawValue {
                                    Text("Install using \(installerName)")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        if model.isHovering {
                            HStack {
                                Spacer()
                                Button(action: model.toggleShowMore) {
                                    Text(model.showMore ? "Show Less" : "Show More")
                                        .font(.footnote)
                                }
                                .buttonStyle(.plain)
                                .background(
                                    Rectangle()
                                        .inset(by: -2)
                                        .fill(.clear)
                                        .background(Color(NSColor.windowBackgroundColor))
                                )
                            }
                        }
                    }
                }
            } icon: {
                letterIcon()
            }
            .opacity(isInstalled && !isEnabled ? 0.5 : 1.0)

            Spacer()

            installationButton()
        }
        .onHover(perform: model.setHovering)
        .alert(
            "Remove \(package.sanitizedName)?",
            isPresented: $model.showingRemovalConfirmation,
            actions: removalActions,
            message: removalMessage
        )
        .alert(
            "Removal Failed",
            isPresented: $model.showingRemovalError,
            actions: removalFailedActions,
            message: removalFailedMessage
        )
    }

    @ViewBuilder
    func removalActions() -> some View {
        Button("Cancel", role: .cancel, action: model.dismissRemovalConfirmation)
        Button("Remove", role: .destructive, action: removeLanguageServer)
    }

    @ViewBuilder
    func removalMessage() -> some View {
        Text("Are you sure you want to remove this language server? This action cannot be undone.")
    }

    @ViewBuilder
    func removalFailedActions() -> some View {
        Button("OK", role: .cancel, action: model.dismissRemovalError)
    }

    @ViewBuilder
    func removalFailedMessage() -> some View {
        Text(model.removalErrorMessage)
    }

    @ViewBuilder
    func installationButton() -> some View {
        if isInstalled {
            installedRow()
        } else if registryManager.runningInstall?.package.name == package.name {
            isInstallingRow()
        } else if model.isHovering {
            isHoveringRow()
        }
    }

    @ViewBuilder
    func installedRow() -> some View {
        HStack {
            if model.isRemoving {
                CECircularProgressView()
                    .frame(width: 20, height: 20)
            } else if model.isHovering {
                Button(action: model.requestRemoval) {
                    Text("Remove")
                }
            }
            Toggle(
                "",
                isOn: Binding(get: { isEnabled }, set: setEnabled)
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        }
    }

    @ViewBuilder
    func isInstallingRow() -> some View {
        HStack {
            ZStack {
                CECircularProgressView()
                    .frame(width: 20, height: 20)

                Button(action: onCancel) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }
    }

    @ViewBuilder
    func failedRow() -> some View {
        Button(action: install) {
            Text("Retry")
                .foregroundColor(.red)
        }
    }

    @ViewBuilder
    func isHoveringRow() -> some View {
        Button(action: install) {
            Text("Install")
        }
        .disabled(registryManager.isInstalling)
    }

    @ViewBuilder
    func letterIcon() -> some View {
        RoundedRectangle(cornerRadius: iconSize / 4, style: .continuous)
            .fill(background)
            .overlay {
                Text(String(package.sanitizedName.first ?? "?"))
                    .font(.system(size: iconSize * 0.65))
                    .foregroundColor(.primary)
            }
            .clipShape(RoundedRectangle(cornerRadius: iconSize / 4, style: .continuous))
            .shadow(
                color: Color(NSColor.black).opacity(0.25),
                radius: iconSize / 40,
                y: iconSize / 40
            )
            .frame(width: iconSize, height: iconSize)
    }

    func install() {
        Task {
            await onInstall(package)
        }
    }

    func setEnabled(_ enabled: Bool) {
        registryManager.setPackageEnabled(packageName: package.name, enabled: enabled)
    }

    func openHomepage() {
        guard let url = package.homepageURL else { return }
        NSWorkspace.shared.open(url)
    }

    func removeLanguageServer() {
        model.remove(packageName: package.name, using: registryManager)
    }

    private var background: AnyShapeStyle {
        let colors: [Color] = [
            .blue, .green, .orange, .red, .purple, .pink, .teal, .yellow, .indigo, .cyan
        ]
        let hashValue = abs(package.sanitizedName.hash) % colors.count
        return AnyShapeStyle(colors[hashValue].gradient)
    }

    static func == (lhs: LanguageServerRowView, rhs: LanguageServerRowView) -> Bool {
        lhs.package.name == rhs.package.name
    }
}
