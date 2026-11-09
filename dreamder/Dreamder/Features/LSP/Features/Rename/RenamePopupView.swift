import SwiftUI

struct RenamePopupView: View {
    @Bindable var model: RenamePopupViewModel
    @FocusState private var fieldFocused: Bool
    @State private var selection: TextSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.prompt)
                .font(Islands.headerTitleFont)
                .foregroundStyle(Islands.foreground)
                .lineLimit(1)
            field
            footer
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPopup()
        .onAppear {
            fieldFocused = true
            selection = TextSelection(range: model.name.startIndex..<model.name.endIndex)
        }
    }

    private var field: some View {
        TextField("New name", text: $model.name, selection: $selection)
            .textFieldStyle(.plain)
            .font(Islands.codeFont)
            .foregroundStyle(Islands.editorForeground)
            .focused($fieldFocused)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: Islands.controlRadius)
                    .fill(Islands.glassFieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Islands.controlRadius)
                    .strokeBorder(
                        model.errorMessage == nil ? Islands.componentBorder : Islands.errorForeground,
                        lineWidth: 1
                    )
            )
    }

    private var footer: some View {
        HStack(spacing: 8) {
            hint
            Spacer(minLength: 8)
            confirmButton
        }
    }

    @ViewBuilder
    private var hint: some View {
        if let message = model.errorMessage {
            Text(message)
                .font(Islands.smallFont)
                .foregroundStyle(Islands.errorForeground)
                .lineLimit(1)
        } else {
            Text(RenameMessages.confirmHint)
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)
                .lineLimit(1)
        }
    }

    private var confirmButton: some View {
        Button(action: model.confirm) {
            Text("Rename")
                .font(Islands.smallFont)
                .foregroundStyle(model.isConfirmEnabled ? Color.white : Islands.disabledForeground)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: Islands.controlRadius)
                        .fill(model.isConfirmEnabled ? Islands.accent : Islands.glassRaisedFill)
                )
        }
        .buttonStyle(.plain)
        .disabled(!model.isConfirmEnabled)
    }
}
