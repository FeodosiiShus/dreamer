//
//  SourceControlAddExistingRemoteView.swift
//  Dreamder
//
//  Created by Austin Condiff on 11/17/23.
//

import SwiftUI

@Observable
@MainActor
final class SourceControlAddExistingRemoteModel {
    var name: String
    var location: String
    @ObservationIgnored var manager: SourceControlManager?
    @ObservationIgnored var dismiss: (() -> Void)?
    @ObservationIgnored private(set) var submission: Task<Void, Never>?

    init(name: String = "", location: String = "") {
        self.name = name
        self.location = location
    }

    func attach(manager: SourceControlManager, dismiss: @escaping () -> Void) {
        self.manager = manager
        self.dismiss = dismiss
    }

    func suggestOriginWhenMissing() -> Bool {
        guard let manager, !manager.remotes.contains(where: { $0.name == "origin" }) else { return false }
        name = "origin"
        return true
    }

    func cancel() {
        dismiss?()
        name = ""
        location = ""
    }

    func submit() {
        submission = Task { await perform() }
    }

    func perform() async {
        guard let manager else { return }
        do {
            try await manager.addRemote(name: name, location: location)
            if manager.pullSheetIsPresented || manager.pushSheetIsPresented {
                manager.operationRemote = manager.remotes.first(where: { $0.name == name })
            }
            name = ""
            location = ""
            dismiss?()
        } catch {
            await manager.showAlertForError(title: "Failed to add remote", error: error)
        }
    }
}

struct SourceControlAddExistingRemoteView: View {
    @Environment(SourceControlManager.self) private var sourceControlManager
    @Environment(\.dismiss)
    private var dismiss

    @State private var model: SourceControlAddExistingRemoteModel

    init(model: SourceControlAddExistingRemoteModel = SourceControlAddExistingRemoteModel()) {
        _model = State(initialValue: model)
    }

    enum FocusedField {
        case name, location
    }

    @FocusState private var focusedField: FocusedField?

    var body: some View {
        @Bindable var form = model
        VStack(spacing: 0) {
            Form {
                Section("Add Remote") {
                    TextField("Remote Name", value: $form.name, formatter: RegexFormatter(pattern: "[^a-zA-Z0-9_-]"))
                        .focused($focusedField, equals: .name)
                    TextField("Location", value: $form.location, formatter: TrimWhitespaceFormatter())
                        .focused($focusedField, equals: .location)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .onSubmit(model.submit)
            HStack {
                Spacer()
                Button(action: model.cancel) {
                    Text("Cancel")
                        .frame(minWidth: 56)
                }
                Button(action: model.submit) {
                    Text("Add")
                        .frame(minWidth: 56)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 500)
        .onAppear {
            model.attach(manager: sourceControlManager, dismiss: dismiss.callAsFunction)
            if model.suggestOriginWhenMissing() {
                focusedField = .location
            }
        }
    }
}
