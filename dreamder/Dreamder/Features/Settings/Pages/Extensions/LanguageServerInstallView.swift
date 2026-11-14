//
//  LanguageServerInstallView.swift
//  Dreamder
//
//  Created by Khan Winter on 8/14/25.
//

import SwiftUI

/// A view for initiating a package install and monitoring progress.
struct LanguageServerInstallView: View {
    @Environment(\.dismiss)
    var dismiss
    let operation: PackageManagerInstallOperation
    let registryManager: RegistryManager
    var settingsWindow: @MainActor () -> NSWindow? = { NSApp.settingsWindow }

    var body: some View {
        VStack(spacing: 0) {
            formContent
            Divider()
            footer
        }
        .constrainHeightToWindow(of: settingsWindow)
        .alert(
            "Confirm Step",
            isPresented: .constant(operation.waitingForConfirmation != nil),
            presenting: operation.waitingForConfirmation,
            actions: confirmationActions,
            message: confirmationMessage
        )
    }

    @ViewBuilder func confirmationActions(_ message: String) -> some View {
        Button("Cancel", action: registryManager.cancelInstallation)
        Button("Continue", action: operation.confirmCurrentStep)
    }

    @ViewBuilder func confirmationMessage(_ message: String) -> some View {
        Text(message)
    }

    @ViewBuilder private var formContent: some View {
        Form {
            packageInfoSection
            errorSection
            if operation.runningState == .running || operation.runningState == .complete {
                progressSection
                outputSection
            } else {
                notInstalledSection
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder var footer: some View {
        HStack {
            Spacer()
            switch operation.runningState {
            case .none:
                Button(action: cancel) {
                    Text("Cancel")
                }
                .buttonStyle(.bordered)
                Button(action: startInstallation) {
                    Text("Install")
                }
                .buttonStyle(.borderedProminent)
            case .running:
                Button(action: cancelInstallationAndDismiss) {
                    Text("Cancel")
                        .frame(minWidth: 56)
                }
                .buttonStyle(.bordered)
            case .complete:
                Button(action: cancel) {
                    Text("Continue")
                        .frame(minWidth: 56)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    func cancel() {
        dismiss()
    }

    func cancelInstallationAndDismiss() {
        registryManager.cancelInstallation()
        dismiss()
    }

    func startInstallation() {
        do {
            try registryManager.startInstallation(operation: operation)
        } catch {
            // Display the error
            NSAlert(error: error).runModal()
        }
    }

    @ViewBuilder private var packageInfoSection: some View {
        Section {
            LabeledContent("Installing Package", value: operation.package.sanitizedName)
            LabeledContent("Homepage") {
                sourceButton.cursor(.pointingHand)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Description")
                Text(operation.package.sanitizedDescription)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(.secondary)
                    .labelsHidden()
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder private var errorSection: some View {
        if let error = operation.error {
            Section {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.octagon.fill").foregroundColor(.red)
                    Text("Error Occurred")
                }
                .font(.title3)
                ErrorDescriptionLabel(error: error)
            }
        }
    }

    @ViewBuilder var sourceButton: some View {
        Button(operation.package.homepagePretty, action: openHomepage)
            .buttonStyle(.plain)
            .foregroundColor(Color(NSColor.linkColor))
            .focusEffectDisabled()
    }

    func openHomepage() {
        guard let homepage = operation.package.homepageURL else { return }
        NSWorkspace.shared.open(homepage)
    }

    @ViewBuilder private var progressSection: some View {
        Section {
            LabeledContent("Step") {
                if registryManager.installedLanguageServers[operation.package.name] != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Successfully Installed")
                            .foregroundStyle(.primary)
                    }
                } else if operation.error != nil {
                    Text("Error Occurred")
                } else {
                    Text(operation.currentStep?.name ?? "")
                }
            }
            ProgressView(value: operation.fractionCompleted ?? 1)
                .progressViewStyle(.linear)
        }
    }

    @ViewBuilder private var outputSection: some View {
        Section {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(operation.accumulatedOutput) { line in
                            VStack {
                                if line.isStepDivider && line != operation.accumulatedOutput.first {
                                    Divider()
                                }
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    ZStack {
                                        if let idx = line.outputIdx {
                                            Text(String(idx))
                                                .font(.caption2.monospaced())
                                                .foregroundStyle(.tertiary)
                                        }
                                        Text(String(10)) // Placeholder for spacing
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.tertiary)
                                            .opacity(0.0)
                                    }
                                    Text(line.contents)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(line.isStepDivider ? .primary : .secondary)
                                        .textSelection(.enabled)
                                    Spacer(minLength: 0)
                                }
                            }
                            .tag(line.id)
                            .id(line.id)
                        }
                    }
                }
                .onChange(of: operation.accumulatedOutput) { _, output in
                    Task {
                        withAnimation(.linear(duration: 0.1)) {
                            proxy.scrollTo(output.last?.id)
                        }
                    }
                }
            }
        }
        .frame(height: 200)
    }

    @ViewBuilder private var notInstalledSection: some View {
        Section {
            if let method = operation.package.installMethod {
                LabeledContent("Install Method", value: method.installerDescription)
                    .textSelection(.enabled)
                if let packageDescription = method.packageDescription {
                    LabeledContent("Package", value: packageDescription)
                        .textSelection(.enabled)
                }
            } else {
                LabeledContent("Installer", value: "Unknown")
            }
        }
    }
}
